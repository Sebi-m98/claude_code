# Invoicing — Toggl → easybill

Drei Varianten — je nachdem was du brauchst:

| Variante | Datei | Was sie macht | Voraussetzung |
|---|---|---|---|
| **Lite (empfohlen für 1 Rechnung/Monat)** | `n8n-workflow-lite.json` | Holt Toggl-Stunden + PDF, schickt dir am 1. eine Mail mit Stunden, Netto/Brutto + PDF im Anhang. Rechnung tippst du manuell in easybill. | n8n + Toggl-Token + SMTP |
| **Full (n8n)** | `n8n-workflow.json` | Wie Lite + legt zusätzlich Draft-Rechnung in easybill an, hängt PDF dran. Du klickst nur noch „senden" in easybill. | n8n + Toggl + **easybill PROFESSIONAL** (API ab 21 €/Monat) |
| **Full (Python-CLI)** | `invoice.py` | Wie Full, aber lokal als Python-Skript. | Python + Toggl + easybill PROFESSIONAL |

---

## Lite-Workflow (`n8n-workflow-lite.json`)

Schickt dir am 1. um 09:00 eine Mail mit Toggl-Übersicht für den Vormonat. Kein easybill-API nötig — kostet 0 € extra.

### 1. Credential in n8n: „Toggl Basic Auth"

n8n → **Credentials** → **+ Add Credential** → **Basic Auth** (Generic):
- Name: `Toggl Basic Auth` (exakt so)
- Username: dein Toggl-API-Token (https://track.toggl.com/profile, ganz unten)
- Password: `api_token` (genau das wörtlich, kein Platzhalter)

### 2. Credential in n8n: „SMTP"

n8n → **Credentials** → **+ Add Credential** → **SMTP**:
- Name: `SMTP` (exakt so)
- Host / Port / User / Password / SSL: laut deinem E-Mail-Anbieter (Gmail, Strato, IONOS, etc.)
  - **Gmail**: `smtp.gmail.com`, Port 465, SSL=true, App-Passwort statt normales PW
  - **IONOS**: `smtp.ionos.de`, Port 465, SSL=true
  - Bei deinem eigenen Hoster: dort nachschauen

### 3. Workflow importieren

n8n → **Workflows** → **+** → **Import from File** → `n8n-workflow-lite.json`.

### 4. Mail-Adresse anpassen

Im Node **„Config"**:
- `to_email` → wo soll die Mail hin? (Default: `info@marxen-ecommerce.com`)
- `from_email` → muss zur SMTP-Credential passen
- `hourly_rate`, `vat_percent` → falls sich was ändert

Workspace-ID musst du *nicht* eintragen — der Workflow holt sie automatisch über `/me`.

### 5. Test + aktivieren

- **„Execute Workflow"** klicken → läuft sofort durch, Mail kommt an.
- Bei Erfolg: Toggle oben rechts auf **Active** → läuft jeden 1. um 09:00.

### Was passiert
```
Schedule (1. 09:00)
  → Date Range (Vormonat berechnen)
  → Toggl /me (workspace_id automatisch holen)
  → Config (Stundensatz, Mail-Adresse)
  → Toggl: Time Entries
  → Sum Hours (Stunden, netto, brutto)
  → Toggl: Detailed PDF
  → Send Email (mit PDF angehängt)
```

---

## Full-Workflow (`n8n-workflow.json`)

> Braucht **easybill PROFESSIONAL** (21 €/Monat) wegen REST-API-Zugang.

Macht das gleiche wie der Lite-Workflow plus: legt automatisch einen Draft in easybill an und hängt das Toggl-PDF dort an. Du gehst in easybill, prüfst, klickst senden.

### 1. Credentials in n8n anlegen

Falls noch nicht vom Lite-Workflow vorhanden, „Toggl Basic Auth" wie [oben beschrieben](#1-credential-in-n8n-toggl-basic-auth) anlegen. Zusätzlich:

**Credential: „easybill Bearer"**
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
