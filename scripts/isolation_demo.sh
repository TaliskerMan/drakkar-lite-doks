#!/usr/bin/env bash
# Proves tenant isolation end to end:
#   1. creates two organizations (A and B)
#   2. A adds a contact
#   3. B lists contacts (expects 0) and fetches A's contact by ID (expects 404)
# Usage: scripts/isolation_demo.sh [base-url]   (default http://localhost:8081)
set -euo pipefail

BASE="${1:-http://localhost:18081}"
STAMP="$(date +%s)"
PASS='Demo-Pass-2026'

json() { python3 -c "import json,sys; print(json.load(sys.stdin)$1)"; }

post() { # path token body
  local auth=()
  [[ -n "$2" ]] && auth=(-H "authorization: Bearer $2")
  curl -fsS -X POST "$BASE$1" -H 'content-type: application/json' "${auth[@]+"${auth[@]}"}" -d "$3"
}

echo "▶ Base URL: $BASE"
TOKEN_A=$(post /v1/auth/signup "" \
  "{\"organization\":\"Org A $STAMP\",\"name\":\"Alice\",\"email\":\"alice+$STAMP@example.com\",\"password\":\"$PASS\"}" \
  | json "['token']")
TOKEN_B=$(post /v1/auth/signup "" \
  "{\"organization\":\"Org B $STAMP\",\"name\":\"Bob\",\"email\":\"bob+$STAMP@example.com\",\"password\":\"$PASS\"}" \
  | json "['token']")
echo "✔ Created Org A and Org B"

CONTACT_ID=$(post /v1/contacts "$TOKEN_A" \
  '{"firstName":"Ada","lastName":"Lovelace","companyName":"Analytical Engines","workEmail":"ada@example.com"}' \
  | json "['id']")
echo "✔ Org A added contact $CONTACT_ID"

COUNT_A=$(curl -fsS "$BASE/v1/contacts" -H "authorization: Bearer $TOKEN_A" | json "['items'].__len__()")
COUNT_B=$(curl -fsS "$BASE/v1/contacts" -H "authorization: Bearer $TOKEN_B" | json "['items'].__len__()")
STATUS_B=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/v1/contacts/$CONTACT_ID" -H "authorization: Bearer $TOKEN_B")
STATUS_NOAUTH=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/v1/contacts")

echo "  Org A sees $COUNT_A contact(s)"
echo "  Org B sees $COUNT_B contact(s)"
echo "  Org B GET Org A's contact → HTTP $STATUS_B"
echo "  No token → HTTP $STATUS_NOAUTH"

if [[ "$COUNT_A" == "1" && "$COUNT_B" == "0" && "$STATUS_B" == "404" && "$STATUS_NOAUTH" == "401" ]]; then
  echo "✅ Tenant isolation holds."
else
  echo "❌ Unexpected result — investigate before the demo." >&2
  exit 1
fi
