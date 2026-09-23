#!/usr/bin/env bash
# ==============================================================================
# Google Cloud Document AI - Automated Provisioning & Deployment Script
# Workload Target: ~25,000 pages/week (~950 SGD / week in AI SKU Consumption)
# ==============================================================================
set -euo pipefail
export PATH="/opt/homebrew/bin:/opt/homebrew/share/google-cloud-sdk/bin:/usr/local/bin:$HOME/google-cloud-sdk/bin:$PATH"
export CLOUDSDK_CONTEXT_AWARE_USE_CLIENT_CERTIFICATE=false

PROJECT_ID="${1:-$(gcloud config get-value project 2>/dev/null || echo 'gcp-sap-analytics-prod')}"
LOCATION="${2:-us}" # Document AI processor multi-region ('us' or 'eu')
BQ_LOCATION="${3:-US}"
INPUT_BUCKET="gs://${PROJECT_ID}-sap-docai-input"
OUTPUT_BUCKET="gs://${PROJECT_ID}-sap-docai-output"
BQ_DATASET="sap_docai_staging"
BQ_TABLE="extracted_sap_documents"

echo "=============================================================================="
echo " Deploying SAP Document AI Pipeline on Google Cloud"
echo " Project ID       : ${PROJECT_ID}"
echo " DocAI Location   : ${LOCATION}"
echo " Input Bucket     : ${INPUT_BUCKET}"
echo " Output Bucket    : ${OUTPUT_BUCKET}"
echo " BigQuery Target  : ${PROJECT_ID}.${BQ_DATASET}.${BQ_TABLE}"
echo "=============================================================================="

# 1. Enable Required Google Cloud APIs
echo "[1/6] Enabling Google Cloud APIs (Document AI, Storage, BigQuery, Cloud Run, Scheduler)..."
gcloud services enable \
  documentai.googleapis.com \
  storage.googleapis.com \
  bigquery.googleapis.com \
  run.googleapis.com \
  cloudscheduler.googleapis.com \
  --project="${PROJECT_ID}"

# 2. Create Cloud Storage Buckets for Batch Input & Output
echo "[2/6] Creating Cloud Storage buckets for PDF Ingestion & Batch Output..."
gcloud storage buckets create "${INPUT_BUCKET}" \
  --project="${PROJECT_ID}" \
  --location="${BQ_LOCATION}" \
  --uniform-bucket-level-access || echo "Bucket ${INPUT_BUCKET} already exists."

gcloud storage buckets create "${OUTPUT_BUCKET}" \
  --project="${PROJECT_ID}" \
  --location="${BQ_LOCATION}" \
  --uniform-bucket-level-access || echo "Bucket ${OUTPUT_BUCKET} already exists."

# 3. Create BigQuery Dataset & SAP Document Staging Table
echo "[3/6] Creating BigQuery dataset and staging table for extracted SAP Invoices & POs..."
bq --location="${BQ_LOCATION}" mk --dataset \
  --description="Staging dataset for Document AI extracted SAP Invoices (VBRK/MIRO) and Customer POs (VBAK)" \
  "${PROJECT_ID}:${BQ_DATASET}" 2>/dev/null || echo "Dataset ${BQ_DATASET} already exists."

bq mk --table \
  --description="Extracted SAP header and line-item data from Document AI Invoice & Custom Extractors" \
  "${PROJECT_ID}:${BQ_DATASET}.${BQ_TABLE}" \
  document_id:STRING,document_type:STRING,sap_document_number:STRING,sap_vendor_lifnr:STRING,sap_customer_kunnr:STRING,document_date:STRING,due_date:STRING,currency:STRING,net_amount:FLOAT,tax_amount:FLOAT,total_amount:FLOAT,confidence_score:FLOAT,source_gcs_uri:STRING,processed_timestamp:TIMESTAMP,raw_entities_json:STRING \
  2>/dev/null || echo "Table ${BQ_TABLE} already exists."

# 4. Provision Document AI Processors via REST API
echo "[4/6] Creating Document AI Processors (Enterprise Invoice Parser & Custom/Form Extractor)..."
ACCESS_TOKEN="$(gcloud auth print-access-token)"
DOCAI_API="https://${LOCATION}-documentai.googleapis.com/v1/projects/${PROJECT_ID}/locations/${LOCATION}/processors"

create_processor() {
  local display_name="$1"
  local proc_type="$2"
  local existing_id
  existing_id=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" "${DOCAI_API}" | \
    python3 -c "import sys, json; data=json.load(sys.stdin); print(next((p['name'].split('/')[-1] for p in data.get('processors', []) if p.get('displayName')=='${display_name}'), ''))")
  
  if [[ -n "${existing_id}" ]]; then
    echo "  -> Found existing ${display_name} (ID: ${existing_id})" >&2
    echo "${existing_id}"
  else
    echo "  -> Provisioning new ${display_name} (${proc_type})..." >&2
    local response
    response=$(curl -s -X POST "${DOCAI_API}" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{\"displayName\": \"${display_name}\", \"type\": \"${proc_type}\"}")
    echo "${response}" | python3 -c "import sys, json; print(json.load(sys.stdin)['name'].split('/')[-1])"
  fi
}

INVOICE_PROCESSOR_ID=$(create_processor "sap-enterprise-invoice-parser" "INVOICE_PROCESSOR")
CUSTOM_PROCESSOR_ID=$(create_processor "sap-po-custom-extractor" "FORM_PARSER_PROCESSOR")

# 5. Save Environment Configuration
cat <<EOF > gcp_docai_config.env
export GCP_PROJECT_ID="${PROJECT_ID}"
export GCP_DOCAI_LOCATION="${LOCATION}"
export GCP_INPUT_BUCKET="${INPUT_BUCKET}"
export GCP_OUTPUT_BUCKET="${OUTPUT_BUCKET}"
export GCP_BQ_DATASET="${BQ_DATASET}"
export GCP_BQ_TABLE="${BQ_TABLE}"
export INVOICE_PROCESSOR_ID="${INVOICE_PROCESSOR_ID}"
export CUSTOM_PROCESSOR_ID="${CUSTOM_PROCESSOR_ID}"
EOF
echo "[5/6] Saved processor IDs and configuration to gcp_docai_config.env"

# 6. Upload Sample PDFs to Google Cloud Storage
echo "[6/6] Uploading sample SAP PDFs to ${INPUT_BUCKET}/incoming/..."
if [[ ! -d "generated_pdfs" ]]; then
  python3 01_generate_sample_sap_pdfs.py --total-pages 30 --pages-per-doc 3
fi
# Upload first 20 PDFs (~60-100 pages) for immediate batch execution (avoids 5000-file glob overflow)
find generated_pdfs -name "*.pdf" | head -n 20 | gcloud storage cp -I "${INPUT_BUCKET}/incoming/"

echo "=============================================================================="
echo " ✅ Setup Complete! To execute batch processing in Google Cloud, run:"
echo "    source gcp_docai_config.env"
echo "    python3 03_run_docai_batch_processor.py"
echo "=============================================================================="
