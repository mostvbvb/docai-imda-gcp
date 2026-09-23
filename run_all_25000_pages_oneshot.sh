#!/usr/bin/env bash
# ==============================================================================
# ONE-SHOT MASTER SCRIPT: Process ALL 25,000 Pages (~950 SGD/week AI Workload)
# 1. Ensures 5,000 PDFs (5 pages each = 25,000 pages) exist locally
# 2. Multi-threaded rsyncs all 5,000 PDFs to Google Cloud Storage
# 3. Fires all 5x1,000-doc Document AI Batch Jobs CONCURRENTLY in parallel
# ==============================================================================
set -euo pipefail
export PATH="/opt/homebrew/bin:/opt/homebrew/share/google-cloud-sdk/bin:/usr/local/bin:$HOME/google-cloud-sdk/bin:$PATH"
export CLOUDSDK_CONTEXT_AWARE_USE_CLIENT_CERTIFICATE=false

PROJECT_ID="${1:-${GCP_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo 'YOUR_GCP_PROJECT_ID')}}"
LOCATION="${2:-${GCP_DOCAI_LOCATION:-us}}"

if [[ "${PROJECT_ID}" == "YOUR_GCP_PROJECT_ID" || -z "${PROJECT_ID}" ]]; then
  echo "ERROR: Please pass your GCP Project ID as the first argument or set GCP_PROJECT_ID in your environment."
  echo "Usage: ./run_all_25000_pages_oneshot.sh <YOUR_GCP_PROJECT_ID> [us|eu]"
  exit 1
fi

echo "=============================================================================="
echo " 🚀 ONE-SHOT SAP DOCUMENT AI PIPELINE (25,000 PAGES / 5,000 PDFS)"
echo " Project ID : ${PROJECT_ID}"
echo " Location   : ${LOCATION}"
echo "=============================================================================="

# 1. Ensure GCP resources & processors exist for this project
if [[ ! -f "gcp_docai_config.env" ]] || grep -q "YOUR_INVOICE_PROCESSOR_ID" gcp_docai_config.env; then
  echo "[1/4] Provisioning GCP Buckets, BigQuery Table & Document AI Processors..."
  bash 02_setup_and_deploy_gcp.sh "${PROJECT_ID}" "${LOCATION}" "US"
fi
export GCP_PROJECT_ID="${PROJECT_ID}"
export GCP_DOCAI_LOCATION="${LOCATION}"
source gcp_docai_config.env

# 2. Ensure all 5,000 PDFs (25,000 pages) are generated locally
PDF_COUNT=$(find generated_pdfs -name "*.pdf" 2>/dev/null | wc -l | tr -d ' ')
if [[ "${PDF_COUNT}" -lt 5000 ]]; then
  echo "[2/4] Generating 5,000 PDFs (25,000 pages total)..."
  python3 01_generate_sample_sap_pdfs.py --total-pages 25000 --pages-per-doc 5
else
  echo "[2/4] Verified ${PDF_COUNT} PDF documents (~25,000 pages) ready in generated_pdfs/"
fi

# 3. Parallel multi-threaded upload of all 5,000 PDFs to Cloud Storage
echo "[3/4] Syncing all 5,000 PDFs to ${GCP_INPUT_BUCKET}/incoming/ via parallel gcloud rsync..."
gcloud storage rsync generated_pdfs "${GCP_INPUT_BUCKET}/incoming" --project="${PROJECT_ID}"

# 4. Launch concurrent Document AI Batch Processing across all 25,000 pages
echo "[4/4] Launching parallel Document AI Batch Processing (5 concurrent jobs x 1,000 docs)..."
python3 03_run_docai_batch_processor.py \
  --mode gcp-batch \
  --project-id "${PROJECT_ID}" \
  --location "${LOCATION}" \
  --batch-size 1000 \
  --process-all
