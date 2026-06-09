#!/usr/bin/env python3
"""Generate a monthly draft invoice in easybill from Toggl tracked hours.

Usage:
    python invoice.py                     # previous month, with confirmation prompt
    python invoice.py --month 2026-04
    python invoice.py --dry-run           # no API writes
    python invoice.py --yes               # skip confirmation
    python invoice.py --list-customers    # print easybill customers and exit
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import date
from pathlib import Path

from dotenv import load_dotenv

import config
from easybill import EasybillClient, EasybillError
from toggl import MonthRange, TogglClient, hours_from_seconds

ROOT = Path(__file__).parent
OUTPUT_DIR = ROOT / config.OUTPUT_DIR


def previous_month() -> tuple[int, int]:
    today = date.today()
    if today.month == 1:
        return today.year - 1, 12
    return today.year, today.month - 1


def parse_month_arg(s: str) -> tuple[int, int]:
    try:
        year_s, month_s = s.split("-")
        year, month = int(year_s), int(month_s)
        if not 1 <= month <= 12:
            raise ValueError
        return year, month
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"--month must be YYYY-MM, got {s!r}") from exc


def fmt_eur(value: float) -> str:
    return f"{value:,.2f} €".replace(",", "X").replace(".", ",").replace("X", ".")


def confirm(prompt: str) -> bool:
    answer = input(f"{prompt} [y/N] ").strip().lower()
    return answer in {"y", "yes", "j", "ja"}


def list_customers_cmd(eb: EasybillClient) -> int:
    customers = eb.list_customers()
    print(f"{'ID':<10} {'Number':<10} {'Company / Name'}")
    for c in customers:
        name = c.get("company_name") or f"{c.get('first_name', '')} {c.get('last_name', '')}".strip()
        print(f"{c.get('id'):<10} {str(c.get('number') or ''):<10} {name}")
    return 0


def run(args: argparse.Namespace) -> int:
    load_dotenv(ROOT / ".env")

    toggl_token = os.environ.get("TOGGL_API_TOKEN", "")
    toggl_workspace = os.environ.get("TOGGL_WORKSPACE_ID", "")
    eb_key = os.environ.get("EASYBILL_API_KEY", "")

    if args.list_customers:
        eb = EasybillClient(eb_key)
        return list_customers_cmd(eb)

    if args.month:
        year, month = args.month
    else:
        year, month = previous_month()
    period = MonthRange.for_month(year, month)
    print(f"Period: {period.start.isoformat()} – {period.end.isoformat()}")

    toggl = TogglClient(toggl_token, toggl_workspace)
    print("Fetching Toggl hours…")
    seconds = toggl.total_seconds(period)
    hours = hours_from_seconds(seconds)
    if hours <= 0:
        print("No tracked hours in this period. Aborting.")
        return 1

    rate = config.HOURLY_RATE_NET_EUR
    vat = config.VAT_PERCENT
    net = round(hours * rate, 2)
    gross = round(net * (1 + vat / 100), 2)

    print()
    print("Invoice preview")
    print("─" * 50)
    print(f"  Customer number  : {config.CUSTOMER_NUMBER}")
    print(f"  Description      : {config.INVOICE_DESCRIPTION}")
    print(f"  Hours (exact)    : {hours}")
    print(f"  Rate (net)       : {fmt_eur(rate)} / h")
    print(f"  Net total        : {fmt_eur(net)}")
    print(f"  VAT {vat}%          : {fmt_eur(round(net * vat / 100, 2))}")
    print(f"  Gross total      : {fmt_eur(gross)}")
    print("─" * 50)

    if args.dry_run:
        print("Dry-run – no API writes. Done.")
        return 0

    if not args.yes and not confirm("Create draft invoice in easybill and attach Toggl PDF?"):
        print("Aborted.")
        return 1

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    toggl_pdf = OUTPUT_DIR / f"toggl_report_{period.label}.pdf"
    print(f"Downloading Toggl detailed PDF → {toggl_pdf}")
    toggl.download_detailed_pdf(period, toggl_pdf)

    eb = EasybillClient(eb_key)
    print(f"Looking up easybill customer (number={config.CUSTOMER_NUMBER})…")
    customer = eb.find_customer_by_number(config.CUSTOMER_NUMBER)
    customer_id = customer["id"]

    print("Creating draft invoice…")
    document = eb.create_invoice_draft(
        customer_id=customer_id,
        description=config.INVOICE_DESCRIPTION,
        quantity=hours,
        single_price_net=rate,
        vat_percent=vat,
    )
    document_id = document["id"]
    print(f"  → document_id = {document_id}")

    print("Uploading Toggl PDF as attachment…")
    try:
        attachment = eb.upload_attachment(toggl_pdf, customer_id=customer_id)
        attachment_id = attachment.get("id")
        if attachment_id:
            eb.attach_file_to_document(document_id, attachment_id)
            print(f"  → attached file id={attachment_id} to document {document_id}")
    except EasybillError as exc:
        print(f"  ! Attachment failed: {exc}")
        print(f"  ! Toggl PDF saved locally at {toggl_pdf} – attach manually in easybill.")

    log = OUTPUT_DIR / f"log_{period.label}.json"
    log.write_text(
        json.dumps(
            {
                "period": period.label,
                "hours": hours,
                "net_eur": net,
                "gross_eur": gross,
                "document_id": document_id,
                "document_number": document.get("number"),
                "toggl_pdf": str(toggl_pdf),
            },
            indent=2,
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )

    print()
    print(f"Draft created. Open in easybill, review, and send manually.")
    print(f"Log written to {log}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--month", type=parse_month_arg, help="Month as YYYY-MM (default: previous month)")
    parser.add_argument("--dry-run", action="store_true", help="Print preview only, no API writes")
    parser.add_argument("--yes", action="store_true", help="Skip confirmation prompt")
    parser.add_argument("--list-customers", action="store_true", help="List easybill customers and exit")
    args = parser.parse_args()
    try:
        return run(args)
    except KeyboardInterrupt:
        print("\nAborted.")
        return 130


if __name__ == "__main__":
    sys.exit(main())
