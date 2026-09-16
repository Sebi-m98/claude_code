#!/usr/bin/env bash
# Registriert n8n per Dynamic Client Registration (RFC 7591) als OAuth-Client beim MCP-Server
# und gibt die Werte aus, die in die generische n8n-Credential "OAuth2 API" gehören.
#
#   ./register-client.sh https://host/mcp https://n8n.deinedomain.de
#
# Danach in n8n: Credentials -> OAuth2 API -> Werte eintragen -> "Connect my account" -> Login-Seite -> fertig.
set -euo pipefail

MCP_URL="${1:-}"; N8N_URL="${2:-}"
[[ -z "$MCP_URL" || -z "$N8N_URL" ]] && { echo "Aufruf: $0 https://host/mcp https://dein-n8n"; exit 1; }
N8N_URL="${N8N_URL%/}"
REDIRECT="$N8N_URL/rest/oauth2-credential/callback"

ORIGIN="$(printf '%s' "$MCP_URL" | sed -E 's#^(https?://[^/]+).*#\1#')"
PATH_PART="$(printf '%s' "$MCP_URL" | sed -E 's#^https?://[^/]+##')"

# --- Authorization Server finden (gleiche Logik wie discover.sh) ---
AS_URL="$ORIGIN"
for u in "$ORIGIN/.well-known/oauth-protected-resource$PATH_PART" "$ORIGIN/.well-known/oauth-protected-resource"; do
  if out="$(curl -sSf "$u" 2>/dev/null)"; then
    AS_URL="$(printf '%s' "$out" | python3 -c 'import json,sys; print((json.load(sys.stdin).get("authorization_servers") or [""])[0])' 2>/dev/null || echo "$ORIGIN")"
    break
  fi
done
AS_ORIGIN="$(printf '%s' "$AS_URL" | sed -E 's#^(https?://[^/]+).*#\1#')"
AS_PATH="$(printf '%s' "$AS_URL" | sed -E 's#^https?://[^/]+##')"
META=""
for u in "$AS_ORIGIN/.well-known/oauth-authorization-server$AS_PATH" "$AS_ORIGIN/.well-known/oauth-authorization-server" \
         "$AS_ORIGIN/.well-known/openid-configuration$AS_PATH" "$AS_ORIGIN/.well-known/openid-configuration"; do
  if META="$(curl -sSf "$u" 2>/dev/null)"; then break; fi
done
[[ -z "$META" ]] && { echo "Keine OAuth-Metadata gefunden - erst ./discover.sh laufen lassen."; exit 2; }

get() { printf '%s' "$META" | python3 -c "import json,sys; v=json.load(sys.stdin).get('$1'); print('' if v is None else (v if isinstance(v,str) else json.dumps(v)))"; }
REG="$(get registration_endpoint)"; AUTHZ="$(get authorization_endpoint)"; TOKEN="$(get token_endpoint)"; SCOPES="$(get scopes_supported)"
[[ -z "$REG" ]] && { echo "Server bietet keine Dynamic Client Registration. Client-ID/-Secret beim Betreiber anfragen."; exit 3; }

# --- Registrieren: erst als Public Client mit PKCE (token_endpoint_auth_method none), sonst mit Secret ---
register() {
  curl -sS -X POST "$REG" -H 'Content-Type: application/json' --data "$(python3 - "$REDIRECT" "$1" <<'EOF'
import json,sys
print(json.dumps({
  "client_name": "n8n Sellerboard Workflows",
  "redirect_uris": [sys.argv[1]],
  "grant_types": ["authorization_code", "refresh_token"],
  "response_types": ["code"],
  "token_endpoint_auth_method": sys.argv[2]
}))
EOF
)"
}
RESP="$(register none)"
if ! printf '%s' "$RESP" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if "client_id" in d else 1)' 2>/dev/null; then
  RESP="$(register client_secret_post)"
fi
CLIENT_ID="$(printf '%s' "$RESP" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("client_id",""))' 2>/dev/null || true)"
CLIENT_SECRET="$(printf '%s' "$RESP" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("client_secret",""))' 2>/dev/null || true)"
[[ -z "$CLIENT_ID" ]] && { echo "Registrierung fehlgeschlagen:"; printf '%s\n' "$RESP"; exit 4; }

SCOPE_STR="$(printf '%s' "$SCOPES" | python3 -c 'import json,sys; s=sys.stdin.read().strip(); print(" ".join(json.loads(s)) if s.startswith("[") else "")' 2>/dev/null || true)"

cat <<EOF

✅ n8n ist als OAuth-Client registriert. In n8n anlegen: Credentials -> "OAuth2 API"

   Grant Type              : PKCE            (falls nicht wählbar: Authorization Code + "PKCE" Option)
   Authorization URL       : $AUTHZ
   Access Token URL        : $TOKEN
   Client ID               : $CLIENT_ID
   Client Secret           : ${CLIENT_SECRET:-<leer lassen>}
   Scope                   : ${SCOPE_STR:-<leer lassen>}
   Auth URI Query Params   : resource=$MCP_URL
   Authentication          : ${CLIENT_SECRET:+Body}${CLIENT_SECRET:-Body (bei leerem Secret egal)}
   Redirect URL (Anzeige)  : $REDIRECT   <- muss exakt der von n8n angezeigten entsprechen

Dann "Connect my account" -> es erscheint dieselbe Login-Seite wie beim claude.ai-Connector -> einloggen -> fertig.
Diese Credential in den drei HTTP-Request-Nodes des Sub-Workflows "SB · MCP Call" auswählen.
EOF
