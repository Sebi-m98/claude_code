#!/usr/bin/env bash
# Findet heraus, wie der Sellerboard-MCP-Server abgesichert ist und was n8n dafür braucht.
#
#   ./discover.sh https://host/mcp
#
# Prüft der Reihe nach:
#   1. Antwortet der Server ohne Token mit 401 + WWW-Authenticate (= OAuth 2.1 nach MCP-Spec)?
#   2. Protected-Resource-Metadata  -> welcher Authorization Server?
#   3. Authorization-Server-Metadata -> authorize/token/registration Endpoints, PKCE, Scopes
# Gibt am Ende eine klare Aussage: DCR ja/nein, PKCE ja/nein, welche n8n-Credential passt.
set -euo pipefail

MCP_URL="${1:-}"
[[ -z "$MCP_URL" ]] && { echo "Aufruf: $0 https://host/mcp"; exit 1; }

ORIGIN="$(printf '%s' "$MCP_URL" | sed -E 's#^(https?://[^/]+).*#\1#')"
PATH_PART="$(printf '%s' "$MCP_URL" | sed -E 's#^https?://[^/]+##')"

json() { python3 -c 'import json,sys; d=json.load(sys.stdin); print(json.dumps(d, indent=2, ensure_ascii=False))' 2>/dev/null || cat; }
field() { python3 -c "import json,sys; d=json.load(sys.stdin); v=d.get('$1'); print(v if not isinstance(v,(list,dict)) else json.dumps(v))" 2>/dev/null || true; }

echo "== 1. Ungeschützter initialize-Call gegen $MCP_URL"
HDRS="$(mktemp)"; BODY="$(mktemp)"
STATUS="$(curl -sS -o "$BODY" -D "$HDRS" -w '%{http_code}' -X POST "$MCP_URL" \
  -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -H 'MCP-Protocol-Version: 2025-06-18' \
  --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"discover","version":"1.0"}}}' || echo "000")"
echo "   HTTP $STATUS"
[[ "$STATUS" == "000" || "$STATUS" == "000000" ]] && { echo "   -> Keine Verbindung (DNS/Proxy/Firewall). Das sagt nichts über den Server aus - von einem Rechner mit freiem Internet erneut laufen lassen."; rm -f "$HDRS" "$BODY"; exit 5; }
WWW="$(grep -i '^www-authenticate:' "$HDRS" | tr -d '\r' || true)"
[[ -n "$WWW" ]] && echo "   $WWW"
[[ "$STATUS" == "200" ]] && { echo "   -> Server antwortet OHNE Auth. n8n braucht dann gar keine Credential."; head -c 400 "$BODY"; echo; exit 0; }

echo
echo "== 2. Protected-Resource-Metadata"
RM_URL="$(printf '%s' "$WWW" | sed -nE 's/.*resource_metadata="([^"]+)".*/\1/p')"
CANDIDATES=()
[[ -n "$RM_URL" ]] && CANDIDATES+=("$RM_URL")
CANDIDATES+=("$ORIGIN/.well-known/oauth-protected-resource$PATH_PART" "$ORIGIN/.well-known/oauth-protected-resource")
AS_URL=""
for u in "${CANDIDATES[@]}"; do
  if out="$(curl -sSf "$u" 2>/dev/null)"; then
    echo "   gefunden: $u"; printf '%s' "$out" | json | sed 's/^/   /'
    AS_URL="$(printf '%s' "$out" | python3 -c 'import json,sys; print((json.load(sys.stdin).get("authorization_servers") or [""])[0])' 2>/dev/null || true)"
    break
  fi
done
[[ -z "$AS_URL" ]] && { echo "   keine Resource-Metadata -> Authorization Server = Origin ($ORIGIN)"; AS_URL="$ORIGIN"; }

echo
echo "== 3. Authorization-Server-Metadata ($AS_URL)"
AS_ORIGIN="$(printf '%s' "$AS_URL" | sed -E 's#^(https?://[^/]+).*#\1#')"
AS_PATH="$(printf '%s' "$AS_URL" | sed -E 's#^https?://[^/]+##')"
META=""
for u in "$AS_ORIGIN/.well-known/oauth-authorization-server$AS_PATH" "$AS_ORIGIN/.well-known/oauth-authorization-server" \
         "$AS_ORIGIN/.well-known/openid-configuration$AS_PATH" "$AS_ORIGIN/.well-known/openid-configuration"; do
  if META="$(curl -sSf "$u" 2>/dev/null)"; then echo "   gefunden: $u"; break; fi
done
[[ -z "$META" ]] && { echo "   KEINE OAuth-Metadata gefunden. Dann ist die Login-Seite kein Standard-OAuth -> Serverbetreiber nach Bearer-Token fragen."; exit 2; }

AUTHZ="$(printf '%s' "$META" | field authorization_endpoint)"
TOKEN="$(printf '%s' "$META" | field token_endpoint)"
REG="$(printf '%s' "$META" | field registration_endpoint)"
PKCE="$(printf '%s' "$META" | field code_challenge_methods_supported)"
SCOPES="$(printf '%s' "$META" | field scopes_supported)"
AUTHM="$(printf '%s' "$META" | field token_endpoint_auth_methods_supported)"
CIMD="$(printf '%s' "$META" | field client_id_metadata_document_supported)"

echo "   authorization_endpoint : $AUTHZ"
echo "   token_endpoint         : $TOKEN"
echo "   registration_endpoint  : ${REG:-<keins>}"
echo "   PKCE                   : ${PKCE:-<nicht angegeben>}"
echo "   token auth methods     : ${AUTHM:-<nicht angegeben>}"
echo "   scopes_supported       : ${SCOPES:-<keine>}"
echo "   client_id_metadata_doc : ${CIMD:-<nein>}"
echo
echo "== Ergebnis für n8n"
if [[ -n "$REG" && "$REG" != "None" ]]; then
  echo "   ✅ Dynamic Client Registration vorhanden."
  echo "      Weg A (einfach):  n8n-Credential 'MCP OAuth2 API', DCR an lassen, 'Connect' klicken -> gleiche Login-Seite wie bei claude.ai."
  echo "      Weg B (HTTP-Request-Nodes, deterministisch): ./register-client.sh $MCP_URL https://DEIN-N8N  -> Client-ID für generische 'OAuth2 API'-Credential."
else
  echo "   ⚠️  Keine DCR. n8n braucht Client-ID/-Secret vom Serverbetreiber (oder der Server nutzt Client-ID-Metadata-Documents: $CIMD)."
fi
rm -f "$HDRS" "$BODY"
