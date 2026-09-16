# Sellerboard-MCP als API für n8n

Der Sellerboard-MCP-Server ist bereits eine HTTP-API: JSON-RPC über POST. n8n spricht das
direkt mit dem normalen HTTP-Request-Node — ohne KI-Agent, ohne Tokenkosten, deterministisch.
Dieses Paket macht daraus drei importierbare Workflows.

```
 Schedule ──► Aufruf bauen ──► [Sub-Workflow "SB · MCP Call"] ──► auswerten ──► Sheet / Slack
                                 │  initialize
                                 │  notifications/initialized
                                 │  tools/call  ◄──┐
                                 │  parsen        │ "preparing"? -> 8 s warten, nochmal
                                 └─ Ergebnis ─────┘
```

| Datei | Zweck |
|---|---|
| `workflows/00-sellerboard-mcp-call.json` | **Die API.** Sub-Workflow, der ein beliebiges MCP-Tool aufruft: Handshake, Session, SSE/JSON-Parsing, Preparing-Retry. Einmal einrichten, überall benutzen. |
| `workflows/01-sellerboard-hourly-kpis.json` | Stündlich: Umsatz, Bestellungen, Netto, Marge, ACoS, TACoS heute vs. gestern → Google-Sheet-Stundenlog, bei Alarm Slack. Merkt sich den letzten Lauf → „+3 Bestellungen letzte Stunde". |
| `workflows/02-sellerboard-restock-alert.json` | Täglich 07:30: alle Produkte mit Reorder-Flag inkl. Menge, Investition, Reichweite → Slack. |
| `scripts/discover.sh` | Zeigt, wie der Server abgesichert ist (OAuth-Metadata, DCR, PKCE). |
| `scripts/register-client.sh` | Registriert n8n als OAuth-Client und druckt die Credential-Werte. |

## Auth: woher n8n die Sellerboard-Zugangsdaten hat

Kurz: **gar nicht.** n8n sieht nie dein Sellerboard-Passwort. Der Server (`mcp.sellerboard.com`) ist
Sellerboards offizieller MCP-Server und spricht OAuth 2.1 mit Dynamic Client Registration — dasselbe,
was beim claude.ai-Connector passiert ist (URL eintragen → Login-Seite → verbunden):

1. n8n registriert sich einmalig selbst als „Client" beim Server (`register-client.sh` oder die
   n8n-Credential *MCP OAuth2 API* mit DCR). Dafür gibt es keine Client-ID zum Abschreiben — jeder Client bekommt seine eigene.
2. Beim Klick auf „Connect my account" schickt n8n dich auf **Sellerboards** Login-Seite. Du loggst dich dort ein,
   Sellerboard fragt „n8n darf auf deine Daten zugreifen?", du bestätigst.
3. Sellerboard schickt n8n einen **Access-Token** (kurzlebig) plus **Refresh-Token** (langlebig). Beides liegt verschlüsselt
   im n8n-Credential-Store. n8n erneuert den Access-Token automatisch — du loggst dich nie wieder ein.
4. Jeder HTTP-Request-Node mit dieser Credential sendet `Authorization: Bearer <token>`. Der Server weiß damit, *wer* fragt,
   und `list_accounts` liefert genau die Sellerboard-Accounts, auf die dieser Login Zugriff hat.

Widerrufen geht jederzeit: Token in Sellerboard (verbundene Apps) oder Credential in n8n löschen.

## Setup (≈ 20 Minuten)

**1. Server prüfen** — auf deinem Rechner (Mac: Terminal, curl und python3 sind vorhanden). Die URL exakt so wie
im claude.ai-Connector eingetragen (mit oder ohne `/mcp` am Ende — das Script sagt dir, ob sie stimmt):

```bash
chmod +x scripts/*.sh
./scripts/discover.sh https://mcp.sellerboard.com
```

**2. n8n als Client registrieren und Credential anlegen:**

```bash
./scripts/register-client.sh https://mcp.sellerboard.com https://n8n.marxen-ecommerce.com
```

Das Script druckt die Felder für eine n8n-Credential vom Typ **OAuth2 API** (Grant Type PKCE).
Anlegen, „Connect my account" klicken → dieselbe Login-Seite → einloggen. n8n hält ab jetzt
Access- und Refresh-Token selbst aktuell.

> n8n-Cloud oder Reverse-Proxy: Die vom Script gedruckte Redirect-URL muss exakt der entsprechen,
> die n8n in der Credential anzeigt. Bei Abweichung `WEBHOOK_URL` in n8n korrekt setzen.

**3. Workflows importieren** (Reihenfolge 00 → 01 → 02):

- In `00` im Node „Vorbereiten" die `MCP_URL` eintragen und in den drei HTTP-Request-Nodes die Credential aus Schritt 2 wählen.
- In `01` und `02` im Node „SB · MCP Call" den Sub-Workflow `00` auswählen.
- `01`: Google-Sheet-ID eintragen (Tab `Stundenlog`, Spalten werden automatisch angelegt) — oder Node löschen. Slack-Channel setzen.
- `02`: Slack-Channel setzen.
- Account-ID ist bereits eingetragen (`a706de72-…`, EUR, 13 EU-Marktplätze).

**4. Testen:** `00` manuell mit Pin-Data `{ "tool": "list_accounts", "arguments": {} }` ausführen.
Kommt `ok: true` mit deinem Account zurück, läuft alles.

## Für Kunden bauen (deren Sellerboard, dein n8n)

Der Token gehört zu einem **Login**, nicht zu einem Account. `list_accounts` liefert alle Accounts, die dieser Login sehen darf.
Daraus folgen zwei saubere Modelle — empfohlen ist Modell A:

**Modell A — Kunde gibt deinem Sellerboard-User Zugriff (Standard für Agenturen/Freelancer).**
Der Kunde legt in Sellerboard unter *Einstellungen → Benutzer* deine E-Mail als Benutzer an (Lesezugriff reicht für alle
Reporting-Workflows). Danach:
- deine bestehende n8n-Credential bleibt, nichts neu verbinden;
- `list_accounts` zeigt jetzt zusätzlich den Kunden-Account mit eigener `account_id`;
- pro Kunde `01`/`02` duplizieren, nur `ACCOUNT_ID` und den Slack-Channel ändern. Bei mehreren Kunden: `ACCOUNT_ID`
  aus einem Google-Sheet „Kunden" (Spalten: Name, account_id, Slack-Channel) lesen und über die Zeilen loopen.
Vorteile: Kunde behält die Kontrolle (kann Rechte einschränken oder dich entfernen), du hast eine Credential, ein Login,
saubere Trennung pro `account_id`. Zusatzabsicherung: `account_id` fest im Workflow, nie aus Eingaben — dann kann kein
Workflow versehentlich einen fremden Account lesen.

**Modell B — eigene n8n-Credential pro Kunde.**
Du legst in n8n eine zweite Credential „Sellerboard MCP – Kunde X" an, klickst „Connect", und **der Kunde** loggt sich auf
der Sellerboard-Seite ein (im Call per Bildschirmfreigabe oder du schickst ihm den Authorize-Link, der auf dein n8n
zurückleitet). Der Token gehört dann seinem Login. Sinnvoll, wenn der Kunde keinen Benutzer anlegen will oder darf.
Nachteil: läuft der Refresh-Token ab oder ändert der Kunde sein Passwort, musst du ihn erneut einloggen lassen.

Nicht machen: Kunden-Passwörter sammeln oder einen „Sammel-Login" bauen. OAuth existiert genau, damit das nicht nötig ist.

**Wichtig für die Kundenabrechnung:** die Rate-Limits gelten *pro Account* (5 Burst, ~3/s). Zehn Kunden stündlich
abzufragen ist also kein Problem, solange die Workflows nacheinander laufen (Schedule-Trigger versetzt, z. B. Minute 0, 5, 10 …).

## Weitere Tools anbinden

Jeder Workflow ruft `00` mit `{ tool, arguments }` auf. Alle 40 Tools des Servers funktionieren so.
Regeln, die der Server erzwingt und die in den Workflows bereits eingebaut sind:

| Regel | Konsequenz in n8n |
|---|---|
| **UTC-Tagesgrenzen.** Zeiträume sind tagesgenau in UTC; `start` muss ein Vielfaches von 86400 sein. Lokale Mitternacht (CEST) liegt im Vortag. | Tag immer via `Math.floor(Date.now()/1000/86400)*86400` bauen, nie aus lokaler Zeit. |
| **`preparing` ist kein Fehler.** `dashboard_period`, `products`, `inventory`, PPC-Tools antworten asynchron. | Sub-Workflow wiederholt automatisch (6 × 8 s), pro Aufruf über `maxAttempts`/`waitSeconds` änderbar. |
| **Warm-up vor Tabelle.** `dashboard_table` und `ppc_dashboard_table` lesen nur, was `*_period` mit **identischen** Argumenten vorbereitet hat. Sonst `NOT_WARMED`. | Zwei Aufrufe von `00` hintereinander, gleiche `account_id`/Zeitraum/Filter. |
| **Rate Limit:** 5 im Burst, dann ~3/s pro Account. | Execute-Workflow-Node im Mode `each` (sequenziell), keine parallelen Schleifen. |
| **Paging:** `products`/`dashboard_table` max. 35 Zeilen, `order_item` 50 und max. 31 Tage. | Seiten-Items bauen wie in `02`. |
| **IDs:** `products`-Filter erwartet interne `ProductID`, keine ASIN. Ein Produkt per ASIN → `search_query`. | Nie beides zusammen übergeben. |
| **Flags sind Strings.** `TimeToReorder`/`RunningOutOfStock` = `"NO"`/`"YES"`. `DaysOfStockLeft = 0` bei `SalesVelocity = 0` heißt „keine Velocity", nicht „leer". | In `02` wird über die Flags gefiltert. |

Beispiel-Aufrufe für eigene Workflows:

```js
// Produkt-P&L der letzten 7 Tage (erst warm, dann lesen)
{ tool: 'dashboard_period', arguments: { account_id, periods: [{ start: heuteUtc - 6*86400, end: heuteUtc }] } }
{ tool: 'dashboard_table',  arguments: { account_id, entry_type: 'product', period_start: heuteUtc - 6*86400, period_end: heuteUtc, page: 1, count: 35, sort: 'netprofit asc' } }

// PPC pro Kampagne, gestern
{ tool: 'ppc_dashboard_period', arguments: { account_id, group_by: 'campaign', periods: [{ start: gesternUtc, end: gesternUtc }] } }
{ tool: 'ppc_dashboard_table',  arguments: { account_id, group_by: 'campaign', period_start: gesternUtc, period_end: gesternUtc, page: 1, count: 35 } }

// Eine ASIN
{ tool: 'dashboard_period', arguments: { account_id, search_query: 'B0CP97V7ZF', periods: [{ start: heuteUtc, end: heuteUtc }] } }
```

## Push / Webhooks

Gibt es nicht — weder im MCP (kein Subscription-Tool) noch bei Sellerboard. Der Server ist ein Wrapper
um Sellerboards internes Backend, das selbst nur periodisch von Amazon zieht. Stündlich ist deshalb die
sinnvolle Obergrenze; Workflow `01` simuliert Push über das Delta zum letzten Lauf.
Für echte Echtzeit-Events (neue Bestellung, Listing-Änderung) sind SP-API Notifications der richtige Kanal —
Sellerboard liefert die Gewinn-Ebene dazu.

## Alternative: KI-Agent in n8n

Für einen Slack-Bot („wie läuft der Tag?") statt festem Reporting: n8n-Credential **MCP OAuth2 API**
(DCR bleibt an, „Connect" klicken) + Node **MCP Client Tool** am AI-Agent. Der Agent bekommt dann alle 40 Tools.
Für Reporting/Alerts ist das der falsche Weg: nicht deterministisch, kostet pro Lauf Tokens.
