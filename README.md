# Google Cloud Document AI Pipeline for SAP Invoices & Purchase Orders
**Target Workload:** ~25,000 pages / week (~950 SGD / week in Google Cloud AI SKU Consumption)

This directory provides an automated, end-to-end deployment and execution toolkit for **Google Cloud Document AI** integrated with **BigQuery** and **SAP S/4HANA / ECC** (`VBAK`, `VBAP`, `VBRK`, `KNA1`).

---

## Architecture & Pipeline Flow

```
[01_generate_sample_sap_pdfs.py] ──► Generates multi-page SAP PDFs (30 test pages or 25,000 weekly pages)
         │
         ▼
[02_setup_and_deploy_gcp.sh]     ──► 1. Enables Document AI, Cloud Storage, BigQuery, Cloud Run APIs
         │                       ──► 2. Creates GCS Input & Output Buckets
         │                       ──► 3. Creates BigQuery Dataset & Staging Table (`extracted_sap_documents`)
         │                       ──► 4. Provisions Document AI Processors (`INVOICE_PROCESSOR` & `FORM_PARSER_PROCESSOR`)
         │                       ──► 5. Uploads PDFs to `gs://${PROJECT_ID}-sap-docai-input/incoming/`
         ▼
[03_run_docai_batch_processor.py]──► Executes asynchronous `BatchProcessRequest` on Google Cloud Document AI
         │                       ──► Parses extracted SAP entities (`LIFNR`, `KUNNR`, `NETWR`, `MWSKZ`, `WAERK`)
         │                       ──► Streams structured records into BigQuery (`sap_docai_staging.extracted_sap_documents`)
         ▼
[04_deploy_cloud_run_job.sh]     ──► Containerizes & deploys as a Google Cloud Run Job + Daily Cloud Scheduler
```

---

## Quick Start & Execution Steps

### Step 1: Generate Sample SAP PDF Pages
By default, 10 multi-page PDF documents (30 pages total) have already been generated in [`generated_pdfs/`](./generated_pdfs).

- **To regenerate the 30-page test batch:**
  ```bash
  python3 01_generate_sample_sap_pdfs.py --total-pages 30 --pages-per-doc 3
  ```
- **To generate the full 25,000-page weekly production volume (~950 SGD/week AI SKU target):**
  ```bash
  python3 01_generate_sample_sap_pdfs.py --total-pages 25000 --pages-per-doc 5
  ```

---

### Step 2: Test & Verify Extraction Locally (Optional Dry-Run)
Verify the generated PDFs and inspect the exact BigQuery JSONL payload before connecting to GCP:
```bash
python3 03_run_docai_batch_processor.py --mode local-verify
```
This outputs [`sample_bigquery_extracted_rows.jsonl`](./sample_bigquery_extracted_rows.jsonl).

---

### Step 3: Enable Document AI & Provision Resources in Google Cloud
Run the automated provisioning script (pass your Google Cloud Project ID as the first argument):
```bash
./02_setup_and_deploy_gcp.sh YOUR_GCP_PROJECT_ID us US
```
**What this script executes in Google Cloud:**
1. Enables `documentai.googleapis.com`, `storage.googleapis.com`, `bigquery.googleapis.com`, `run.googleapis.com`, and `cloudscheduler.googleapis.com`.
2. Creates `gs://YOUR_GCP_PROJECT_ID-sap-docai-input` and `gs://YOUR_GCP_PROJECT_ID-sap-docai-output`.
3. Creates BigQuery table `YOUR_GCP_PROJECT_ID.sap_docai_staging.extracted_sap_documents`.
4. Calls the Document AI REST API to create two processors:
   - `sap-enterprise-invoice-parser` (`INVOICE_PROCESSOR`)
   - `sap-po-custom-extractor` (`FORM_PARSER_PROCESSOR`)
5. Saves processor IDs into `gcp_docai_config.env` and uploads the generated PDFs to Cloud Storage.

---

### Step 4: Execute Google Cloud Document AI Batch Processing
Load the generated environment variables and execute the live Document AI batch job:
```bash
source gcp_docai_config.env
pip install google-cloud-documentai google-cloud-storage google-cloud-bigquery
python3 03_run_docai_batch_processor.py --mode gcp-batch
```

---

### Step 5: Deploy Automated Production Schedule (Cloud Run Job + Cloud Scheduler)
To run this pipeline automatically every day in Google Cloud (e.g., in `asia-southeast1` Singapore region to process ~3,570 pages/day = 25,000 pages/week):
```bash
./04_deploy_cloud_run_job.sh asia-southeast1
```
