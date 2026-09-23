#!/usr/bin/env python3
"""Generates realistic multi-page SAP Vendor Invoices and Customer Purchase Orders

in valid PDF format for testing and executing Google Cloud Document AI
(Enterprise Invoice Parser & Custom Document Extractor).

Supports generating a quick test sample (e.g., 30 pages) or scaling up to
25,000 pages/week (--total-pages 25000) for full Google Cloud throughput
execution.
"""

import argparse
from datetime import datetime, timedelta
from pathlib import Path
import random
from typing import List, Tuple

OUTPUT_DIR = Path(__file__).parent / "generated_pdfs"

SAP_VENDORS = [
    ("0000100542", "Global Industrial Components Pte Ltd", "Singapore", "SG"),
    ("0000100881", "Precision Microelectronics Asia Ltd", "Singapore", "SG"),
    ("0000101204", "ASEAN Chemical & Polymer Supply Co", "Jurong East, SG", "SG"),
    ("0000103910", "Pacific Automation & Robotics GmbH", "Munich / SG Branch", "DE"),
]

SAP_CUSTOMERS = [
    ("0000200891", "APAC Manufacturing Hub Pte Ltd", "Tuas South Ave 3, Singapore 637360"),
    ("0000201102", "Southeast Asia Logistics & Distribution", "Changi Business Park, SG 486066"),
    ("0000204519", "Marina Bay Retail Operations Pte Ltd", "10 Bayfront Ave, Singapore 018956"),
]

SAP_MATERIALS = [
    ("MAT-884920-SG", "High-Precision Servo Motor 400V", "EA", 450.00),
    ("MAT-109432-SG", "Industrial PLC Controller Module S7", "EA", 1250.00),
    ("MAT-339201-SG", "Optical Fiber Sensor Array 24V", "PC", 185.50),
    ("MAT-550192-SG", "Stainless Steel Pneumatic Valve 1/2in", "EA", 92.00),
    ("MAT-774810-SG", "Heavy Duty Conveyor Belt Assembly 10m", "SET", 3200.00),
    ("MAT-992011-SG", "Thermal Management Cooling Fan Unit", "EA", 140.00),
]


def _escape_pdf_text(text: str) -> str:
  return text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def create_multipage_pdf(pages_lines: List[List[str]], output_path: Path) -> None:
  """Writes a valid, multi-page standard PDF file using pure Python (zero external dependencies)."""
  objects = []

  # Object 1: Catalog
  objects.append(b"1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n")

  # Object 2: Pages (placeholder, updated below)
  objects.append(b"")

  # Object 3: Font (Helvetica & Helvetica-Bold)
  objects.append(
      b"3 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>\nendobj\n"
  )

  page_obj_ids = []
  next_obj_id = 4

  for lines in pages_lines:
    content_obj_id = next_obj_id
    page_obj_id = next_obj_id + 1
    next_obj_id += 2
    page_obj_ids.append(page_obj_id)

    # Build PDF content stream
    stream_lines = ["BT", "/F1 10 Tf", "40 790 Td", "14 TL"]
    for line in lines:
      escaped = _escape_pdf_text(line)
      stream_lines.append(f"({escaped}) Tj T*")
    stream_lines.append("ET")
    stream_data = "\n".join(stream_lines).encode("latin-1", errors="replace")

    content_obj = (
        f"{content_obj_id} 0 obj\n<< /Length {len(stream_data)} >>\nstream\n".encode("ascii")
        + stream_data
        + b"\nendstream\nendobj\n"
    )
    page_obj = (
        f"{page_obj_id} 0 obj\n"
        f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 842] "
        f"/Resources << /Font << /F1 3 0 R >> >> /Contents {content_obj_id} 0 R >>\n"
        f"endobj\n"
    ).encode("ascii")

    objects.append(content_obj)
    objects.append(page_obj)

  kids_str = " ".join(f"{pid} 0 R" for pid in page_obj_ids)
  objects[1] = (
      f"2 0 obj\n<< /Type /Pages /Kids [{kids_str}] /Count {len(page_obj_ids)} >>\nendobj\n"
  ).encode("ascii")

  # Assemble PDF with xref table
  pdf_bytes = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
  offsets = []
  for obj in objects:
    offsets.append(len(pdf_bytes))
    pdf_bytes.extend(obj)

  xref_offset = len(pdf_bytes)
  pdf_bytes.extend(f"xref\n0 {len(objects) + 1}\n".encode("ascii"))
  pdf_bytes.extend(b"0000000000 65535 f \n")
  for off in offsets:
    pdf_bytes.extend(f"{off:010d} 00000 n \n".encode("ascii"))

  pdf_bytes.extend(
      f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\n"
      f"startxref\n{xref_offset}\n%%EOF\n".encode("ascii")
  )
  output_path.write_bytes(pdf_bytes)


def build_invoice_or_po_pages(
    doc_index: int, pages_per_doc: int, doc_type: str = "INVOICE"
) -> List[List[str]]:
  """Generates structured text lines for each page of an SAP Invoice or Purchase Order."""
  vendor_id, vendor_name, vendor_city, vendor_country = SAP_VENDORS[
      doc_index % len(SAP_VENDORS)
  ]
  cust_id, cust_name, cust_addr = SAP_CUSTOMERS[doc_index % len(SAP_CUSTOMERS)]
  doc_date = (datetime(2026, 9, 1) + timedelta(days=doc_index % 25)).strftime(
      "%Y-%m-%d"
  )
  due_date = (datetime(2026, 10, 1) + timedelta(days=doc_index % 25)).strftime(
      "%Y-%m-%d"
  )

  if doc_type == "INVOICE":
    doc_number = f"INV-2026-{900000 + doc_index}"
    ref_po = f"4500{100000 + doc_index}"
    title = "TAX INVOICE / SAP VENDOR INVOICE (MIRO / VBRK)"
  else:
    doc_number = f"PO-4500{100000 + doc_index}"
    ref_po = f"QT-2000{50000 + doc_index}"
    title = "CUSTOMER PURCHASE ORDER / SAP SALES ORDER (VBAK / VA01)"

  pages: List[List[str]] = []
  total_net = 0.0
  item_counter = 10

  for page_num in range(1, pages_per_doc + 1):
    lines = [
        "=" * 74,
        f"  {title}",
        "=" * 74,
        f"Document Number : {doc_number:<22} Document Date : {doc_date}",
        f"Reference Order : {ref_po:<22} Due Date      : {due_date}",
        f"SAP Client      : 100                    Company Code  : 1000 (SG01)",
        f"Currency        : SGD                    Page          : {page_num} of {pages_per_doc}",
        "-" * 74,
        f"SUPPLIER / VENDOR (LIFNR: {vendor_id}):",
        f"  {vendor_name}",
        f"  {vendor_city}, {vendor_country}",
        "",
        f"SOLD-TO / BILL-TO CUSTOMER (KUNNR: {cust_id}):",
        f"  {cust_name}",
        f"  {cust_addr}",
        "-" * 74,
        "POSNR  MATERIAL SKU     DESCRIPTION                        QTY   UNIT    NET (SGD)",
        "-" * 74,
    ]

    # Add 6 line items per page
    for _ in range(6):
      mat_sku, mat_desc, mat_unit, unit_price = SAP_MATERIALS[
          (doc_index + item_counter) % len(SAP_MATERIALS)
      ]
      qty = float(((doc_index + item_counter) % 9) + 1)
      line_net = round(qty * unit_price, 2)
      total_net += line_net
      lines.append(
          f"{item_counter:04d}   {mat_sku:<16} {mat_desc[:32]:<32} {qty:>5.1f}  {mat_unit:<4} {line_net:>11,.2f}"
      )
      item_counter += 10

    lines.append("-" * 74)

    if page_num == pages_per_doc:
      tax_amt = round(total_net * 0.09, 2)
      grand_total = round(total_net + tax_amt, 2)
      lines.extend([
          f"{'SUBTOTAL (NET AMOUNT / NETWR)':>56} : SGD {total_net:>12,.2f}",
          f"{'SINGAPORE GST / TAX (9% MWSKZ=G9)':>56} : SGD {tax_amt:>12,.2f}",
          "=" * 74,
          f"{'TOTAL AMOUNT DUE (GROSS TOTAL)':>56} : SGD {grand_total:>12,.2f}",
          "=" * 74,
          "",
          "SAP Posting Metadata:",
          f"  Target SAP Tables : VBAK / VBAP / VBRK / VBRP (Client MANDT=100)",
          f"  Payment Terms     : Z030 (Net 30 Days)",
          f"  Authorized Signature: [ Digitally Signed - SAP EDI Gateway ]",
      ])
    else:
      lines.extend([
          f"{' running subtotal carried to next page...':>56}   SGD {total_net:>12,.2f}",
          "=" * 74,
          f"Continued on Page {page_num + 1}...",
      ])

    pages.append(lines)

  return pages


def main() -> None:
  parser = argparse.ArgumentParser(
      description="Generate multi-page SAP Invoices & PO PDFs for Google Cloud Document AI."
  )
  parser.add_argument(
      "--total-pages",
      type=int,
      default=30,
      help=(
          "Total number of PDF pages to generate. Default is 30 pages (10 docs x 3 pages) "
          "for quick deployment testing. Set --total-pages 25000 to generate the full "
          "weekly 25,000-page batch (~950 SGD/week AI workload)."
      ),
  )
  parser.add_argument(
      "--pages-per-doc",
      type=int,
      default=3,
      help="Number of pages per PDF document (default: 3).",
  )
  args = parser.parse_args()

  OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
  num_docs = max(1, args.total_pages // args.pages_per_doc)
  actual_total_pages = num_docs * args.pages_per_doc

  print(
      f"Generating {num_docs} multi-page SAP PDF documents "
      f"({args.pages_per_doc} pages/doc = {actual_total_pages} total pages)..."
  )

  for i in range(1, num_docs + 1):
    doc_type = "INVOICE" if i % 2 == 1 else "PURCHASE_ORDER"
    prefix = "SAP_INV" if doc_type == "INVOICE" else "SAP_PO"
    filename = OUTPUT_DIR / f"{prefix}_{20260000 + i}_{args.pages_per_doc}p.pdf"
    pages_content = build_invoice_or_po_pages(i, args.pages_per_doc, doc_type)
    create_multipage_pdf(pages_content, filename)

  print(f"✅ Successfully generated {num_docs} PDFs ({actual_total_pages} pages) in:")
  print(f"   {OUTPUT_DIR}")
  print(
      "\n💡 Tip: To generate the full 25,000-page weekly volume for stress-testing "
      "or full production simulation, run:"
  )
  print("   python3 01_generate_sample_sap_pdfs.py --total-pages 25000 --pages-per-doc 5")


if __name__ == "__main__":
  main()
