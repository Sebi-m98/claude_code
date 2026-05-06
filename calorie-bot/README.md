# Telegram Kalorientracker

Ein persönlicher Telegram-Bot fürs Kalorien- und Makro-Tracking. Schick ihm
Text, Fotos oder EAN-Barcodes; er loggt alles in dein Google Sheet.

## Was er macht

- **Text** ("2 Eier mit Toast und Butter") → Gemini zerlegt + schätzt;
  Markenprodukte werden gegen [Open Food Facts](https://world.openfoodfacts.org)
  geprüft.
- **Foto** vom Teller → Gemini Vision schätzt Items, Portionsgrößen und Makros.
- **EAN-Barcode** (z.B. `4008400123456`) → Open Food Facts Lookup, dann fragt
  der Bot nach der Menge.
- Jeder Eintrag muss kurz mit ✅/❌ bestätigt werden, bevor er ins Sheet geht.
- `/heute` zeigt deine Tagesbilanz.
- `/undo` entfernt den letzten Eintrag.

Das Sheet hat drei Tabs:

| Tab          | Inhalt                                          |
| ------------ | ----------------------------------------------- |
| `Log`        | Rohdaten, jede Mahlzeit eine Zeile              |
| `Heute`      | Live-Tagesbilanz (Formeln, aktualisiert sich)   |
| `Übersicht`  | Tagesweise Aggregation, neuester Tag oben       |

---

## Setup

Du brauchst dafür ca. 20 Minuten und drei kostenlose Accounts:
Telegram, Google AI Studio, Google Cloud.

### 1. Code holen + Python einrichten

```bash
cd calorie-bot
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
```

### 2. Telegram Bot anlegen

1. Schreib in Telegram an **[@BotFather](https://t.me/BotFather)**.
2. `/newbot` → Name + Username vergeben.
3. Du bekommst einen Token wie `1234567890:ABC...`. Den in `.env` als
   `TELEGRAM_BOT_TOKEN=...` eintragen.

Optional: Schreib **[@userinfobot](https://t.me/userinfobot)** an, um deine
eigene User-ID rauszufinden, und setz `ALLOWED_USER_IDS=<deine ID>` in `.env`,
damit nur du den Bot benutzen kannst.

### 3. Gemini API Key

1. Geh auf [aistudio.google.com/apikey](https://aistudio.google.com/apikey)
   (mit deinem normalen Google-Account einloggen).
2. "Create API Key" klicken.
3. Als `GEMINI_API_KEY=AIza...` in `.env` eintragen.

Kostenrahmen: Gemini 2.5 Flash hat ein großzügiges Free Tier
(1500 Requests/Tag). Bei normalem privaten Tracken bleibst du locker drin.
Auch im Paid Tier extrem günstig — pro Mahlzeit ca. 0,01–0,1 Cent.

### 4. Google Sheet + Service Account

Der Bot braucht einen Google Service Account, damit er ohne Login ins Sheet
schreiben kann.

**a) Cloud-Projekt anlegen:**

1. Geh zu [console.cloud.google.com](https://console.cloud.google.com).
2. Oben "Projekt auswählen" → "Neues Projekt" → Name z.B. `calorie-bot`.

**b) Sheets + Drive API aktivieren:**

1. Im Projekt: "APIs & Services" → "Bibliothek".
2. Such "Google Sheets API" → Aktivieren.
3. Such "Google Drive API" → Aktivieren.

**c) Service Account erstellen:**

1. "APIs & Services" → "Anmeldedaten".
2. "Anmeldedaten erstellen" → "Dienstkonto".
3. Name z.B. `calorie-bot-writer`, Rolle leer lassen, fertig.
4. Auf das neue Dienstkonto klicken → Tab "Schlüssel" → "Schlüssel hinzufügen"
   → "Neuen Schlüssel erstellen" → JSON.
5. Die heruntergeladene Datei als `credentials.json` ins `calorie-bot/`-Verzeichnis legen.
6. Die Email-Adresse des Service Accounts merken (steht in der JSON, sieht aus
   wie `calorie-bot-writer@<projekt>.iam.gserviceaccount.com`).

**d) Sheet erstellen + teilen:**

1. Auf [sheets.google.com](https://sheets.google.com) ein leeres Sheet anlegen,
   z.B. "Kalorientracker".
2. URL ansehen: `https://docs.google.com/spreadsheets/d/<DIESE_ID>/edit` — den
   Teil zwischen `/d/` und `/edit` als `GOOGLE_SHEETS_ID` in `.env` eintragen.
3. Im Sheet oben rechts "Teilen" → die Service-Account-Email aus Schritt c)
   einfügen, Rolle "Bearbeiter", "Senden".

**e) Tabs einrichten:**

```bash
python setup_sheets.py
```

Das Script legt die drei Tabs an, formatiert Header und richtet die
Live-Formeln ein. Falls schon Tabs vorhanden sind, werden sie geleert und neu
aufgebaut.

### 5. Bot starten

```bash
python main.py
```

Schreib deinem Bot in Telegram `/start` — er sollte antworten.

---

## Bot benutzen

| Du schickst…                              | Was passiert                                  |
| ----------------------------------------- | --------------------------------------------- |
| `2 Eier mit Toast und Butter`             | Gemini parst, OFF-Lookup, Bestätigung         |
| `Skyr Natur 200g`                         | Gemini parst, OFF findet Skyr Natur           |
| `selbstgemachte Lasagne 350g`             | Gemini schätzt direkt (kein OFF-Treffer)      |
| `4008400123456` (EAN)                     | OFF Barcode-Lookup, Bot fragt nach Gramm      |
| 📷 Foto vom Teller                        | Gemini Vision schätzt alle erkannten Items    |
| `/heute`                                  | Heutige Summen                                |
| `/undo`                                   | Letzten Eintrag löschen                       |

Vor jedem Logging zeigt der Bot dir die Schätzung — mit ✅ bestätigen oder mit
❌ verwerfen.

---

## Wo laufen lassen?

Der Bot ist ein simpler Long-Polling-Prozess, also überall lauffähig wo Python
läuft:

- **Lokal** — solange dein Rechner an ist, läuft der Bot. Einfachster Start.
- **Raspberry Pi** — perfekt, weil 24/7 an. `tmux` oder als systemd-Service
  starten.
- **Cloud (kostenlos/günstig)** — z.B. [Railway](https://railway.app),
  [Fly.io](https://fly.io), [Render](https://render.com) Free Tier. Pack
  einfach `python main.py` als Start-Command rein.

Beispiel systemd-Unit für Raspberry Pi (`/etc/systemd/system/calorie-bot.service`):

```ini
[Unit]
Description=Telegram Calorie Bot
After=network-online.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi/calorie-bot
ExecStart=/home/pi/calorie-bot/.venv/bin/python main.py
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Dann `sudo systemctl enable --now calorie-bot`.

---

## Troubleshooting

**"Fehlende Konfiguration"** beim Start
→ `.env` nicht vollständig. Vergleich mit `.env.example`.

**"Konnte das Sheet gerade nicht lesen"**
→ Sheet-ID falsch, oder Service Account hat keinen Zugriff. Sheet erneut mit
der Service-Account-Email teilen (mit Bearbeiter-Rolle).

**Bot reagiert nicht**
→ Schau in die Konsole, wo `main.py` läuft. Telegram-Errors stehen da.

**OFF findet nichts trotz korrektem Barcode**
→ Das Produkt ist noch nicht in OFF. Trag es selbst auf
[world.openfoodfacts.org](https://world.openfoodfacts.org) ein (Crowd-Datenbank)
oder schick die Beschreibung als Text — Gemini schätzt dann.

**Falsche Schätzungen bei Fotos**
→ Vision ist nicht perfekt. Bessere Fotos (gut beleuchtet, von oben, mit
Bezug zur Tellergröße) helfen. Oder Text als Korrektur schicken.

**Eintrag ins falsche Datum gerutscht (Mitternacht)**
→ Bot nutzt aktuelle Server-Zeit. Falls dein Server in einer anderen Zeitzone
läuft, in `.env` die Variable `TZ=Europe/Berlin` setzen.

---

## Architektur

```
┌──────────┐     ┌──────────────┐     ┌──────────────┐
│ Telegram │────▶│   main.py    │────▶│   Gemini     │
└──────────┘     │  (Handlers)  │     │  (Vision +   │
                 └──────┬───────┘     │   Parsing)   │
                        │             └──────────────┘
                        │
              ┌─────────┴─────────┐
              ▼                   ▼
       ┌─────────────┐     ┌────────────────┐
       │ Open Food   │     │ Google Sheets  │
       │ Facts       │     │ (Log + Heute + │
       │ (Marken)    │     │  Übersicht)    │
       └─────────────┘     └────────────────┘
```

| Datei              | Funktion                                     |
| ------------------ | -------------------------------------------- |
| `main.py`          | Telegram-Handler, Bestätigungs-Flow          |
| `ai_estimator.py`  | Gemini API für Text-Parsing + Bild-Analyse   |
| `food_lookup.py`   | Open Food Facts Wrapper                      |
| `sheets.py`        | Google Sheets Schreib-/Leseoperationen       |
| `setup_sheets.py`  | Einmaliges Sheet-Setup                       |
| `config.py`        | `.env` Loader                                |
