"""
Einmaliges Setup-Script fuer das Google Sheet.

Legt drei Tabs an und richtet Formatierung + Formeln ein:
- Log         Rohdaten
- Heute       Live-Tagesuebersicht
- Übersicht   Tageweise Aggregation

Benutzung: python setup_sheets.py
"""
from __future__ import annotations

import sys

import gspread
from google.oauth2.service_account import Credentials
from gspread.exceptions import WorksheetNotFound

import config
import sheets

ACCENT_BG = {"red": 0.18, "green": 0.36, "blue": 0.32}  # dunkles Gruen
ACCENT_FG = {"red": 1.0, "green": 1.0, "blue": 1.0}
SOFT_BG = {"red": 0.93, "green": 0.96, "blue": 0.94}


def _open_spreadsheet() -> gspread.Spreadsheet:
    creds = Credentials.from_service_account_file(
        config.GOOGLE_CREDENTIALS_PATH, scopes=sheets.SCOPES
    )
    client = gspread.authorize(creds)
    return client.open_by_key(config.GOOGLE_SHEETS_ID)


def _get_or_create(sh: gspread.Spreadsheet, title: str, rows: int, cols: int) -> gspread.Worksheet:
    try:
        return sh.worksheet(title)
    except WorksheetNotFound:
        return sh.add_worksheet(title=title, rows=rows, cols=cols)


def setup_log(ws: gspread.Worksheet) -> None:
    print(f"Richte '{ws.title}' ein...")
    ws.clear()
    ws.append_row(sheets.LOG_HEADERS, value_input_option="USER_ENTERED")
    ws.freeze(rows=1)
    ws.format(
        "A1:J1",
        {
            "backgroundColor": ACCENT_BG,
            "textFormat": {"foregroundColor": ACCENT_FG, "bold": True},
            "horizontalAlignment": "CENTER",
        },
    )
    ws.format("D2:H", {"numberFormat": {"type": "NUMBER", "pattern": "0.0"}})


def setup_heute(ws: gspread.Worksheet) -> None:
    print(f"Richte '{ws.title}' ein...")
    ws.clear()

    # Layout
    ws.update(
        range_name="A1",
        values=[
            ["📅 Heute", '=TEXT(TODAY(); "TT.MM.YYYY")'],
            [],
            ["🔥 Kalorien", '=SUMIFS(Log!E:E; Log!A:A; TODAY())', "kcal"],
            ["🥩 Eiweiß", '=SUMIFS(Log!F:F; Log!A:A; TODAY())', "g"],
            ["🍞 Kohlenhydrate", '=SUMIFS(Log!G:G; Log!A:A; TODAY())', "g"],
            ["🧈 Fett", '=SUMIFS(Log!H:H; Log!A:A; TODAY())', "g"],
            [],
            ["Heutige Einträge:"],
        ],
        value_input_option="USER_ENTERED",
    )
    ws.update(
        range_name="A10",
        values=[["Zeit", "Mahlzeit", "Menge (g)", "kcal", "Eiweiß (g)", "KH (g)", "Fett (g)"]],
    )
    ws.update(
        range_name="A11",
        values=[
            [
                '=IFERROR(QUERY(Log!A:J; '
                '"select B, C, D, E, F, G, H where A = \'"&TEXT(TODAY();"yyyy-mm-dd")&"\' '
                'order by B desc"); "Noch keine Einträge heute.")'
            ]
        ],
        value_input_option="USER_ENTERED",
    )

    # Formatierung
    ws.format(
        "A1:B1",
        {
            "backgroundColor": ACCENT_BG,
            "textFormat": {"foregroundColor": ACCENT_FG, "bold": True, "fontSize": 14},
        },
    )
    ws.format("A3:A6", {"textFormat": {"bold": True}})
    ws.format(
        "B3:B6",
        {
            "textFormat": {"bold": True, "fontSize": 16},
            "horizontalAlignment": "RIGHT",
            "numberFormat": {"type": "NUMBER", "pattern": "0"},
        },
    )
    ws.format("A8", {"textFormat": {"bold": True, "fontSize": 11}})
    ws.format(
        "A10:G10",
        {
            "backgroundColor": SOFT_BG,
            "textFormat": {"bold": True},
        },
    )

    # Spaltenbreiten via batch_update
    sheet_id = ws.id
    body = {
        "requests": [
            {
                "updateDimensionProperties": {
                    "range": {"sheetId": sheet_id, "dimension": "COLUMNS", "startIndex": 0, "endIndex": 1},
                    "properties": {"pixelSize": 180},
                    "fields": "pixelSize",
                }
            },
            {
                "updateDimensionProperties": {
                    "range": {"sheetId": sheet_id, "dimension": "COLUMNS", "startIndex": 1, "endIndex": 2},
                    "properties": {"pixelSize": 220},
                    "fields": "pixelSize",
                }
            },
        ]
    }
    ws.spreadsheet.batch_update(body)


def setup_uebersicht(ws: gspread.Worksheet) -> None:
    print(f"Richte '{ws.title}' ein...")
    ws.clear()
    ws.update(
        range_name="A1",
        values=[["📊 Tagesübersicht (alle Tage, neueste zuerst)"]],
    )
    ws.update(
        range_name="A3",
        values=[
            [
                '=IFERROR(QUERY(Log!A:H; '
                '"select A, sum(E), sum(F), sum(G), sum(H) '
                'where A is not null and A <> \'Datum\' '
                'group by A order by A desc '
                'label A \'Datum\', sum(E) \'kcal\', sum(F) \'Eiweiß (g)\', '
                'sum(G) \'KH (g)\', sum(H) \'Fett (g)\'"; 0); '
                '"Noch keine Daten.")'
            ]
        ],
        value_input_option="USER_ENTERED",
    )
    ws.format(
        "A1",
        {
            "backgroundColor": ACCENT_BG,
            "textFormat": {"foregroundColor": ACCENT_FG, "bold": True, "fontSize": 13},
        },
    )
    ws.format(
        "A3:E3",
        {
            "backgroundColor": SOFT_BG,
            "textFormat": {"bold": True},
        },
    )
    ws.format("B4:E", {"numberFormat": {"type": "NUMBER", "pattern": "0"}})
    ws.freeze(rows=3)


def main() -> int:
    try:
        sh = _open_spreadsheet()
    except Exception as e:
        print(f"Fehler beim Öffnen des Sheets: {e}", file=sys.stderr)
        print("Pruefe GOOGLE_SHEETS_ID in .env und ob das Sheet mit dem Service Account geteilt ist.")
        return 1

    log_ws = _get_or_create(sh, "Log", rows=5000, cols=10)
    heute_ws = _get_or_create(sh, "Heute", rows=200, cols=10)
    uebersicht_ws = _get_or_create(sh, "Übersicht", rows=400, cols=10)

    setup_log(log_ws)
    setup_heute(heute_ws)
    setup_uebersicht(uebersicht_ws)

    # Standardmaessig zuerst angelegtes "Tabellenblatt1" loeschen, falls vorhanden
    for default_name in ("Tabellenblatt1", "Sheet1"):
        try:
            sh.del_worksheet(sh.worksheet(default_name))
            print(f"'{default_name}' entfernt.")
        except WorksheetNotFound:
            pass

    print("\n✅ Setup fertig. URL:")
    print(f"   https://docs.google.com/spreadsheets/d/{config.GOOGLE_SHEETS_ID}/edit")
    return 0


if __name__ == "__main__":
    sys.exit(main())
