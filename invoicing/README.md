# Invoicing — Toggl → easybill

Erzeugt am Monatsanfang einen **Entwurf** in easybill auf Basis der Toggl-Stunden des Vormonats und hängt den Toggl-Detailreport als PDF an. Versand bleibt manuell in easybill (du klickst „senden" im Draft).

## Setup

```bash
cd invoicing
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
```

`.env` ausfüllen:

| Variable              | Wo finden                                                                      |
|-----------------------|--------------------------------------------------------------------------------|
| `TOGGL_API_TOKEN`     | https://track.toggl.com/profile (ganz unten)                                  |
| `TOGGL_WORKSPACE_ID`  | Toggl-Web: nach Login in der URL `/workspaces/<ID>` oder per API ermittelbar  |
| `EASYBILL_API_KEY`    | easybill → Einstellungen → Schnittstellen → API-Schlüssel                     |

`config.py` enthält die Defaults aus der bisherigen Rechnung (Kunde 10001, 23,80 €/h netto, 19 % USt, Beschreibung „Freelance Amazon Accountmanagement"). Anpassen wenn nötig.

## Nutzung

```bash
# Vormonat, mit Vorschau + Bestätigungs-Prompt
python invoice.py

# Bestimmter Monat
python invoice.py --month 2026-04

# Nur Preview, keine API-Writes (zum Testen)
python invoice.py --dry-run

# Ohne Rückfrage (für späteren cron)
python invoice.py --yes

# easybill-Kunden auflisten (zum Verifizieren der Kundennummer)
python invoice.py --list-customers
```

## Ablauf

1. Stunden aus Toggl Reports v3 ziehen (alle Einträge im Monat, exakt aufsummiert).
2. Vorschau mit Stunden, Netto-/Brutto-Beträgen, Bestätigungs-Prompt.
3. Toggl-Detailreport als PDF runterladen → `output/toggl_report_YYYY-MM.pdf`.
4. Kunde in easybill per Kundennummer suchen.
5. Draft-Rechnung in easybill anlegen (`status=DRAFT`, eine Position).
6. Toggl-PDF in easybill hochladen und an den Draft anhängen.
7. Log nach `output/log_YYYY-MM.json`.
8. **Du** öffnest den Draft in easybill, prüfst, klickst senden.

## Cronjob (optional, nach 1–2 erfolgreichen manuellen Läufen)

Am 1. jedes Monats um 09:00:

```cron
0 9 1 * * cd /pfad/zu/invoicing && .venv/bin/python invoice.py --yes >> output/cron.log 2>&1
```

Die Mail bleibt trotzdem manuell — `--yes` überspringt nur den Konsolen-Prompt, nicht den easybill-Versand.
