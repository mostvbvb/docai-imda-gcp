FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir \
    google-cloud-documentai>=2.29.0 \
    google-cloud-storage>=2.14.0 \
    google-cloud-bigquery>=3.17.0

COPY 01_generate_sample_sap_pdfs.py .
COPY 03_run_docai_batch_processor.py .

ENTRYPOINT ["python3", "03_run_docai_batch_processor.py", "--mode", "gcp-batch"]
