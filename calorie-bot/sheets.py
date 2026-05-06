"""
Google Sheets Logging.

Drei Tabs:
- "Log"        Rohdaten, jede Mahlzeit eine Zeile
- "Heute"      Live-Tagesuebersicht (per Formeln aus Log generiert)
- "Uebersicht" Tageweise Aggregation der letzten Tage
"""
from __future__ import annotations

import logging
from datetime import date, datetime
from typing import Iterable

import gspread
from google.oauth2.service_account import Credentials

import config

logger = logging.getLogger(__name__)

SCOPES = [
    "https://www.googleapis.com/auth/spreadsheets",
    "https://www.googleapis.com/auth/drive",
]

LOG_HEADERS = [
    "Datum",
    "Zeit",
    "Mahlzeit",
    "Menge (g)",
    "kcal",
    "Eiweiß (g)",
    "KH (g)",
    "Fett (g)",
    "Quelle",
    "Notiz",
]

_client: gspread.Client | None = None


def _get_client() -> gspread.Client:
    global _client
    if _client is None:
        creds = Credentials.from_service_account_file(
            config.GOOGLE_CREDENTIALS_PATH, scopes=SCOPES
        )
        _client = gspread.authorize(creds)
    return _client


def _open_log_sheet() -> gspread.Worksheet:
    sh = _get_client().open_by_key(config.GOOGLE_SHEETS_ID)
    return sh.worksheet("Log")


def append_entries(entries: Iterable[dict]) -> None:
    """Schreibt Items ans Ende der Log-Tabelle. Ein Item = ein Dict mit:
    name, grams, kcal, protein, carbs, fat, source, notes (optional).
    """
    ws = _open_log_sheet()
    now = datetime.now()
    rows = []
    for e in entries:
        rows.append([
            now.strftime("%Y-%m-%d"),
            now.strftime("%H:%M"),
            e["name"],
            round(float(e["grams"]), 1),
            round(float(e["kcal"]), 1),
            round(float(e["protein"]), 1),
            round(float(e["carbs"]), 1),
            round(float(e["fat"]), 1),
            e.get("source", ""),
            e.get("notes", ""),
        ])
    if rows:
        ws.append_rows(rows, value_input_option="USER_ENTERED")


def today_totals() -> dict:
    """Holt die heutigen Summen aus dem Log."""
    ws = _open_log_sheet()
    rows = ws.get_all_values()[1:]  # ohne Header
    today = date.today().strftime("%Y-%m-%d")
    totals = {"kcal": 0.0, "protein": 0.0, "carbs": 0.0, "fat": 0.0, "items": 0}
    for row in rows:
        if not row or row[0] != today:
            continue
        try:
            totals["kcal"] += float((row[4] or "0").replace(",", "."))
            totals["protein"] += float((row[5] or "0").replace(",", "."))
            totals["carbs"] += float((row[6] or "0").replace(",", "."))
            totals["fat"] += float((row[7] or "0").replace(",", "."))
            totals["items"] += 1
        except (ValueError, IndexError):
            continue
    return totals


def remove_last_entry() -> dict | None:
    """Loescht den letzten Log-Eintrag. Gibt das geloeschte Item zurueck oder None."""
    ws = _open_log_sheet()
    rows = ws.get_all_values()
    if len(rows) <= 1:
        return None
    last = rows[-1]
    ws.delete_rows(len(rows))
    return {
        "datum": last[0],
        "zeit": last[1],
        "name": last[2],
        "kcal": last[4],
    }
