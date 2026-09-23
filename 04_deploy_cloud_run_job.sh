#!/usr/bin/env bash
# ==============================================================================
# Deploy SAP Document AI Batch Processor as a Google Cloud Run Job + Cloud Scheduler
# Executes automatically to process ~25,000 pages/week (~3,570 pages/day)
# ==============================================================================
set -euo pipefail
export PATH="/opt/homebrew/bin:/opt/homebrew/share/google-cloud-sdk/bin:/usr/local/bin:$HOME/google-cloud-sdk/bin:$PATH"
export CLOUDSDK_CONTEXT_AWARE_USE_CLIENT_CERTIFICATE=false

if [[ -f "gcp_docai_config.env" ]]; then
  source gcp_docai_config.env
fi

PROJECT_ID="${GCP_PROJECT_ID:-$(gcloud config get-value project)}"
REGION="${1:-asia-southeast1}" # Singapore GCP Region for Cloud Run Job
JOB_NAME="sap-docai-batch-processor-job"
IMAGE_URI="gcr.io/${PROJECT_ID}/${JOB_NAME}:latest"

echo "=============================================================================="
echo " Building and Deploying Cloud Run Job: ${JOB_NAME}"
echo " Region: ${REGION} (Singapore)"
echo "=============================================================================="

# 1. Build container image using Cloud Build
echo "[1/3] Building container image via Google Cloud Build..."
gcloud builds submit --tag "${IMAGE_URI}" --project="${PROJECT_ID}" .

# 2. Create or update Cloud Run Job
echo "[2/3] Creating Cloud Run Job ${JOB_NAME}..."
gcloud run jobs deploy "${JOB_NAME}" \
  --image="${IMAGE_URI}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --task-timeout=3600s \
  --memory=2Gi \
  --set-env-vars="GCP_PROJECT_ID=${PROJECT_ID},GCP_DOCAI_LOCATION=${GCP_DOCAI_LOCATION:-us},INVOICE_PROCESSOR_ID=${INVOICE_PROCESSOR_ID:-},GCP_INPUT_BUCKET=${GCP_INPUT_BUCKET:-},GCP_OUTPUT_BUCKET=${GCP_OUTPUT_BUCKET:-},GCP_BQ_DATASET=${GCP_BQ_DATASET:-sap_docai_staging},GCP_BQ_TABLE=${GCP_BQ_TABLE:-extracted_sap_documents}"

# 3. Create Cloud Scheduler to trigger daily at 02:00 SGT (~3,570 pages/day = 25,000 pages/week)
echo "[3/3] Creating Cloud Scheduler trigger (Daily 02:00 SGT)..."
SERVICE_ACCOUNT="$(gcloud iam service-accounts list --project="${PROJECT_ID}" --filter="email ~ compute@developer.gserviceaccount.com" --format="value(email)" | head -n 1)"

gcloud scheduler jobs create http "${JOB_NAME}-daily-trigger" \
  --location="${REGION}" \
  --project="${PROJECT_ID}" \
  --schedule="0 2 * * *" \
  --time-zone="Asia/Singapore" \
  --uri="https://${REGION}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${PROJECT_ID}/jobs/${JOB_NAME}:run" \
  --http-method=POST \
  --oauth-service-account-email="${SERVICE_ACCOUNT}" \
  2>/dev/null || echo "Scheduler job ${JOB_NAME}-daily-trigger already exists."

echo "=============================================================================="
echo " ✅ Cloud Run Job & Daily Scheduler deployed successfully!"
echo "    To trigger an immediate execution on Google Cloud, run:"
echo "    gcloud run jobs execute ${JOB_NAME} --region=${REGION} --project=${PROJECT_ID}"
echo "=============================================================================="
