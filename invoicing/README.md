# Invoicing — Toggl → easybill

Erzeugt am Monatsanfang einen **Entwurf** in easybill auf Basis der Toggl-Stunden des Vormonats und hängt den Toggl-Detailreport als PDF an. Versand bleibt manuell in easybill (du klickst „senden" im Draft).

Zwei Wege:
- **A) n8n-Workflow** (`n8n-workflow.json`) — empfohlen wenn du n8n eh laufen hast. [Anleitung](#a-n8n-workflow)
- **B) Python-CLI** — wenn du es lokal/per cron laufen lassen willst. [Anleitung](#b-python-cli)

---

## A) n8n-Workflow

Der Workflow `n8n-workflow.json` macht genau das gleiche wie das Python-Skript: Stunden aus Toggl ziehen, Draft in easybill anlegen, Toggl-PDF dranhängen.

### 1. Credentials in n8n anlegen

n8n öffnen → links **Credentials** → **+ Add Credential**:

**Credential 1: „Toggl Basic Auth"**
- Typ: **Basic Auth** (Generic)
- Name: `Toggl Basic Auth` (exakt so, sonst findet der Workflow sie nicht)
- Username: dein Toggl-API-Token (https://track.toggl.com/profile, ganz unten)
- Password: `api_token` (genau das wörtlich, kein Platzhalter)

**Credential 2: „easybill Bearer"**
- Typ: **Header Auth** (Generic)
- Name: `easybill Bearer` (exakt so)
- Header-Name: `Authorization`
- Header-Wert: `Bearer DEIN_EASYBILL_API_KEY` (das Wort „Bearer", Leerzeichen, dann der Key)

### 2. Workflow importieren

n8n → **Workflows** → **+** → **Import from File** → `n8n-workflow.json` auswählen.

### 3. Workspace-ID setzen

Im importierten Workflow den Node **„Config"** öffnen und bei `workspace_id` deine Toggl-Workspace-ID eintragen (zu finden in der Toggl-Web-URL nach Login: `…/workspaces/<DIE_ZAHL>/…`).

Falls du andere Werte brauchst (Kundennummer, Stundensatz, USt %, Beschreibung), auch hier ändern — alle Defaults stehen im Config-Node.

### 4. Test

- **„Execute Workflow"** klicken → läuft sofort durch (für den letzten abgeschlossenen Monat).
- Bei Erfolg: Draft erscheint in easybill mit angehängter Toggl-PDF.

### 5. Aktivieren

Wenn der Test sauber war: oben rechts den Toggle auf **Active** stellen → läuft automatisch jeden 1. um 09:00.

### Was der Workflow macht

```
Schedule (1. 09:00)
  → Config (Stundensatz, Kundennr, USt, Workspace-ID)
  → Date Range (Vormonat berechnen)
  → Toggl: Get Time Entries (Stunden ziehen)
  → Sum Hours (aufsummieren, netto/brutto rechnen)
  → Toggl: Get Detailed PDF (Bericht als PDF runterladen)
  → easybill: Find Customer (Kunde per Nummer suchen)
  → Pick Customer ID (interne ID extrahieren)
  → easybill: Create Draft Invoice (Entwurf anlegen)
  → easybill: Upload Toggl PDF (PDF hochladen)
  → easybill: Link Attachment (PDF an den Entwurf hängen)
```

Versand bleibt manuell — du gehst in easybill, prüfst den Entwurf, klickst senden.

---

## B) Python-CLI

### Setup

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
