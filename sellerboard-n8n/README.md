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

## Auth: warum die Login-Seite genau das Richtige ist

Der Connector wurde in claude.ai nur per URL angebunden, dann kam eine Login-Seite. Das ist
**OAuth 2.1 mit Dynamic Client Registration** — claude.ai hat sich selbst als Client registriert
und dich auf die Login-Seite des Servers geschickt. n8n kann exakt dasselbe. Es gibt keine
Client-ID zum Abschreiben, weil jeder Client seine eigene bekommt.

## Setup (≈ 20 Minuten)

**1. Server prüfen** (MCP-URL steht in claude.ai → Settings → Connectors → SellerBoard):

```bash
chmod +x scripts/*.sh
./scripts/discover.sh https://host/mcp
```

**2. n8n als Client registrieren und Credential anlegen:**

```bash
./scripts/register-client.sh https://host/mcp https://dein-n8n.example.com
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
