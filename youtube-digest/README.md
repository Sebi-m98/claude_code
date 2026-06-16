# AI Video Digest — n8n Workflow

Täglich 12:00 Europe/Berlin: alle neuen Videos der konfigurierten YouTube-Playlist
holen → Transkript via Apify → Key-Points via Gemini 2.5 Flash → HTML-Mail an
`recipient_email` → State im Google Sheet (idempotent über `video_id`).

Das **Transkript** wird ab sofort bei jedem Lauf mit in die Sheet-Spalte
`transcript` geschrieben (neue, 11. Spalte). Bei Videos ohne abrufbares
Transkript (Gemini-Video-Direkt-Modus) bleibt die Zelle leer und
`transcript_status` = `no_transcript`.

## Dateien

- `workflow.json` — der tägliche Digest-Workflow.
- `backfill-transcripts.json` — **einmaliger** Helfer, der die Transkripte für
  die bereits im Sheet stehenden Videos nachträgt. Siehe Abschnitt
  „Transkript-Backfill" unten.

## Import

1. n8n → Workflows → **Import from File** → `workflow.json`
2. Credentials neu zuordnen (Google Sheets, Gmail, YouTube OAuth2 — die IDs
   aus dem Export passen nur, wenn die Credentials lokal denselben internen
   `id` haben; bei Neu-Import einfach in jedem betroffenen Node die Credential
   aus dem Dropdown wählen).
3. **Tokens setzen** (siehe unten — Platzhalter ersetzen).
4. Workflow aktivieren.

## Tokens / Secrets

Im `Config`-Node stehen Platzhalter:

- `apify_token` → `REPLACE_WITH_APIFY_TOKEN`
- `gemini_api_key` → `REPLACE_WITH_GEMINI_API_KEY`

**Empfehlung**: Statt direkt im Set-Node:

- Apify: HTTP-Header-Auth-Credential anlegen (`Authorization: Bearer <token>`)
  und im `Apify Transcript`-Node verwenden — dann Token aus URL entfernen.
- Gemini: Header-Auth-Credential mit `x-goog-api-key: <key>` und im
  `Gemini Key Points`-Node verwenden — dann `?key=…` aus URL entfernen.

So liegt kein Klartext-Secret im Workflow-JSON.

## Was an der Original-Version gefixt wurde

| # | Problem | Fix |
|---|---------|-----|
| 1 | `Get a playlist`-Node hing als toter Ast an `Get Playlist Items` (kein Output verbunden). | Node entfernt, Connection bereinigt. |
| 2 | `Parse Transcript` und `Parse Gemini Response` mappten Antworten **per Index** zurück auf die Quell-Items. Bei `onError: continueRegularOutput` + Retries kann das auseinanderlaufen. | Auf `itemMatching($itemIndex)` umgestellt mit Index-Fallback. |
| 3 | Apify-Token + Gemini-Key im Klartext im Workflow-Export. | Durch Platzhalter ersetzt; README dokumentiert Credential-Variante. |
| 4 | `Apify Transcript` und `Gemini Key Points` (HTTP Request) waren auf `typeVersion 4.4` exportiert — auf älteren n8n-Versionen erscheinen sie als "Install this node to use it" und Connections gehen verloren. | Auf `typeVersion 4.2` gesenkt (stable seit n8n 1.30). Falls die Instanz noch älter ist: weiter auf `4.1`. |
| 5 | `Get Sheet Existing` lieferte beim leeren State-Sheet (Initial-Run) 0 Items — n8n stoppt den Workflow per Default. | `alwaysOutputData: true` gesetzt; `Cache Existing IDs` und `Filter New` sind bereits robust gegen leere Inputs. |
| 6 | `Mark Sent` warf `Column names were updated after the node's setup`, weil sein Schema nur `video_id` + `summary_sent_at` kannte, das Sheet aber von `Append OK` schon mit allen 10 Spalten befüllt war. | Schema im `Mark Sent` auf alle 10 Sheet-Spalten erweitert; `value`-Mapping bleibt auf den zwei Spalten (Rest unverändert beim Update). |
| 7 | Das rohe Transkript wurde nie persistiert — nur `key_points`. | Neue Spalte `transcript`: `Parse Gemini Response` reicht `meta.transcript` (auf 49.000 Zeichen gekappt, Sheets-Zelllimit) durch, `Append OK` schreibt sie, `Mark Sent`-Schema kennt sie. |

## Transkript-Backfill (einmalig, `backfill-transcripts.json`)

Die bereits im Sheet stehenden ~61 Videos haben **kein** gespeichertes
Transkript (die Spalte gab es vorher nicht). Dieser eigenständige Workflow holt
sie nach — unabhängig vom täglichen Digest.

**Warum ein eigener Workflow und nicht „direkt eingetragen"?** In das Google
Sheet schreiben darf nur n8n (dort liegt die OAuth-Credential). Ein externes
Direkt-Schreiben ins Sheet ist hier nicht möglich, daher dieser One-Shot.

**Ablauf:** `Run Backfill` → liest alle Zeilen → filtert die mit leerer
`transcript`-Zelle → Schleife (1 Video/Durchlauf, schont Apify-Rate-Limit) →
Apify-Transkript → `appendOrUpdate` schreibt `transcript` + `transcript_status`
gematcht über `video_id`.

**So benutzt du ihn:**
1. `backfill-transcripts.json` in n8n importieren.
2. Im `Config`-Node `apify_token` setzen (gleicher Token wie im Daily).
3. Google-Sheets-Credential im `Get All Rows`- und `Update Transcript`-Node
   zuordnen.
4. `Run Backfill` klicken. Läuft sequenziell durch alle Videos (~10–20 Min bei 61).

**Eigenschaften:**
- **Idempotent:** Verarbeitet nur Zeilen mit leerer `transcript`-Zelle.
  Erneutes Ausführen holt genau die nach, die beim letzten Mal leer blieben
  (z. B. Apify-Timeout) — bereits gefüllte werden übersprungen.
- **Erwartbare Abdeckung:** ~31 Videos hatten ein abrufbares Transkript
  (`transcript_status: ok`), ~15–20 nicht (echte Caption-Sperre/Live/Privat).
  Für letztere bleibt die Zelle leer und `transcript_status` = `no_transcript`;
  da half im Daily nur Geminis Video-Direkt-Analyse, es gibt also schlicht
  keinen Transkript-Text. Höhere Abdeckung ginge nur über eine andere Quelle
  (anderer Apify-Actor, Supadata, oder Audio→Whisper) — auf Wunsch nachrüstbar.
- **`cellFormat: RAW`** beim Schreiben, damit Transkripte mit führendem
  `=`/`+`/`@` nicht als Sheets-Formel interpretiert werden.

## Bekannte Schwachstellen (nicht gefixt — Designentscheidung)

- **`Append OK` schreibt auch fehlerhafte Items ins Sheet** (`no_transcript`,
  Gemini-Fehler). Folge: solche Videos werden beim nächsten Lauf **nicht
  erneut versucht**. Wenn du Retries willst, in `Append OK` einen Filter
  `transcript_status === 'ok' && !key_points.startsWith('(')` davor schalten.
- **`Get Sheet Existing` lädt das ganze Sheet**. Bei >5k Zeilen merkst du
  das. Optimierung: Range auf `A:A` (nur `video_id`-Spalte) begrenzen.
- **Apify-Token in URL** statt Header → landet in n8n-Logs/Traces.
  Siehe Empfehlung oben.

## State Sheet Schema

Sheet-ID: `1EfVBDj8QVgyUkSMGZMsmYTCXWmRh_ri0x4oDHLizOCw`, Tab `Videos`,
Spalten:

```
video_id | title | channel | url | published_at | added_to_playlist_at | language | transcript_status | key_points | summary_sent_at | transcript
```

`transcript` ist die neue 11. Spalte. n8n legt sie beim ersten Schreiben (Daily
`Append OK` oder Backfill `Update Transcript`) automatisch an — du musst den
Header nicht von Hand setzen. `video_id` ist der Match-Key für `Mark Sent`
und den Backfill (appendOrUpdate).

## Test-Lauf

`Manual Test` Trigger im Editor klicken → Workflow läuft genauso wie der
Schedule-Lauf. Wenn die Playlist keine neuen Videos hat, endet er sauber
nach `Filter New` mit 0 Items (kein Mail-Versand).
