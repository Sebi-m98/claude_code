# Telegram Kalorientracker — n8n Workflow

Importiere `workflow.json` in dein n8n und du hast einen Telegram-Bot der
Mahlzeiten per Text, Foto oder EAN-Barcode in dein Google Sheet loggt.

## Workflow-Logik

```
Telegram Trigger ─► Switch
                     ├── 📷 Foto      → Gemini Vision      → Sheet + Reply
                     ├── 🔢 Barcode   → Open Food Facts    → Sheet + Reply
                     └── 📝 Text      → Gemini 2.5 Flash   → Sheet + Reply
```

13 Nodes, drei parallele Pfade die alle in dem gleichen Sheet-Append +
Telegram-Reply enden.

---

## Was du brauchst

1. **n8n** läuft (n8n.cloud, self-hosted Docker, Pi etc.)
2. **Telegram Bot Token** vom [@BotFather](https://t.me/BotFather)
3. **Gemini API Key** von [aistudio.google.com/apikey](https://aistudio.google.com/apikey) — kostenloses Free Tier reicht locker
4. **Google Sheet** mit Tab `Log` und passenden Headern (siehe unten)
5. **Google Account** für Sheets-OAuth in n8n

---

## Setup in 5 Minuten

### 1. Google Sheet vorbereiten

Erstell ein neues Sheet. In Tab `Log` (umbenennen falls "Tabellenblatt1") trage
Zeile 1 als Header ein:

| A     | B    | C        | D         | E    | F          | G      | H        | I      | J     |
| ----- | ---- | -------- | --------- | ---- | ---------- | ------ | -------- | ------ | ----- |
| Datum | Zeit | Mahlzeit | Menge (g) | kcal | Eiweiß (g) | KH (g) | Fett (g) | Quelle | Notiz |

Optional: zweiten Tab `Heute` anlegen mit folgenden Formeln (zeigt Live-Bilanz):

```
A1:  📅 Heute               B1:  =TEXT(TODAY();"TT.MM.YYYY")
A3:  🔥 Kalorien            B3:  =SUMIFS(Log!E:E;Log!A:A;TODAY())     C3:  kcal
A4:  🥩 Eiweiß              B4:  =SUMIFS(Log!F:F;Log!A:A;TODAY())     C4:  g
A5:  🍞 Kohlenhydrate       B5:  =SUMIFS(Log!G:G;Log!A:A;TODAY())     C5:  g
A6:  🧈 Fett                B6:  =SUMIFS(Log!H:H;Log!A:A;TODAY())     C6:  g
```

Die Sheet-ID ist der Teil zwischen `/d/` und `/edit` in der URL — die brauchst
du gleich.

### 2. n8n Credentials anlegen

In n8n unter **Credentials → Add Credential**:

**a) Telegram Bot**
- Type: `Telegram API`
- Access Token: Token vom BotFather
- Speichern als z.B. "Telegram Bot"

**b) Gemini (HTTP Header Auth)**
- Type: `Header Auth`
- Name: `x-goog-api-key`
- Value: Dein Gemini API Key (`AIza...`)
- Speichern als z.B. "Gemini API Key"

**c) Google Sheets**
- Type: `Google Sheets OAuth2 API`
- Klick durch den OAuth-Flow (n8n erklärt's)
- Speichern als z.B. "Google Sheets"

### 3. Workflow importieren

In n8n: **Workflows → Import from File →** `workflow.json` auswählen.

### 4. Credentials zuordnen

Öffne die importierten Nodes und zeig die "Credentials"-Felder. Du siehst
"Missing"-Hinweise. Für jeden Node das richtige Credential auswählen:

| Node                  | Credential zuordnen     |
| --------------------- | ----------------------- |
| Telegram Trigger      | Telegram Bot            |
| Telegram: Antworten   | Telegram Bot            |
| Gemini Vision         | Gemini API Key          |
| Gemini Text           | Gemini API Key          |
| Sheets: Append        | Google Sheets           |

### 5. Sheet-ID eintragen

Im Node **Sheets: Append**:
- Document → Klick auf "By ID" oder das Feld → deine Sheet-ID einfügen
- Sheet → "Log" auswählen

### 6. Workflow aktivieren

Schalter oben rechts auf **Active**. Schreib deinem Bot in Telegram —
sollte funktionieren.

---

## Bot benutzen

| Du schickst…                  | Was passiert                               |
| ----------------------------- | ------------------------------------------ |
| `2 Eier mit Toast und Butter` | Gemini parst + schätzt + loggt             |
| `Skyr Natur 200g`             | Gemini erkennt Marke + Menge + loggt       |
| `selbstgemachte Lasagne 350g` | Gemini schätzt + loggt                     |
| `4008400123456` (EAN)         | Open Food Facts Lookup, 100g default       |
| 📷 Foto vom Teller            | Gemini Vision schätzt alle Items + loggt   |

**Trade-offs gegenüber dem Python-Bot:**
- Keine Bestätigungs-Buttons — wird direkt geloggt. Falsch geloggte Einträge
  manuell im Sheet löschen.
- Kein `/heute` Befehl — schau direkt im Sheet (oder in den optionalen
  `Heute`-Tab mit den Live-Formeln).
- Bei EAN immer 100g default — andere Mengen als Text nachschicken
  ("Skyr Natur 200g"), nicht als Barcode.

---

## Troubleshooting

**"Missing credentials"** beim Aktivieren
→ Schritt 4 nochmal durchgehen, jedem Node ein Credential zuordnen.

**Telegram-Webhook funktioniert nicht** (n8n.cloud)
→ Workflow muss auf "Active" stehen. Trigger-Node hat eine Webhook-URL die
n8n automatisch bei Telegram registriert.

**Telegram-Webhook bei self-hosted n8n**
→ Du brauchst eine öffentliche HTTPS-URL (z.B. via Tailscale Funnel,
Cloudflare Tunnel, ngrok oder echte Domain mit SSL). Sonst kann Telegram den
Bot nicht erreichen.

**HTTP 401/403 von Gemini**
→ API Key falsch eingetragen. In Credentials → "Gemini API Key" → der
Wert muss im Header `x-goog-api-key` sitzen, ohne `Bearer ` davor. Auch
prüfen ob der Key im AI Studio nicht eingeschränkt ist.

**Sheet nicht beschreibbar**
→ Beim ersten Append fragt Google evtl. nach erweiterten OAuth-Berechtigungen.
Re-authorize unter Credentials → Google Sheets.

**Foto-Branch funktioniert nicht**
→ Telegram Trigger Node muss "Download Files" auf `true` haben (ist im JSON
schon gesetzt; prüf nach Import).

**Gemini-Antwort ist kein gültiges JSON**
→ Sehr selten. Im "Foto: Parse" / "Text: Parse" Node den Error Output
aktivieren und schauen was zurückkommt.

---

## Wo das hier herkommt

Dies ist die n8n-Variante. Eine alternative Implementation als reiner
Python-Bot findest du im `calorie-bot/` Verzeichnis dieses Repos — gleicher
Funktionsumfang plus Bestätigungs-Buttons und `/heute` / `/undo` Befehle, dafür
ohne n8n.
