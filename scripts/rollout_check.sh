#!/usr/bin/env bash
# Sends a steady stream of API requests and reports anything that isn't HTTP 200,
# plus which pod answered. Run it, then `kubectl -n drakkar rollout restart
# deploy/drakkar-api` in another terminal: a correct rollout shows no failures.
# Usage: scripts/rollout_check.sh <base-url> [seconds]   (Ctrl-C to stop early)
set -uo pipefail

BASE="${1:?usage: rollout_check.sh <base-url> [seconds]}"
SECONDS_TO_RUN="${2:-90}"
STAMP="$(date +%s)"

# A base URL without a scheme makes curl assume http://, which since the TLS
# work means every request gets the 301 redirect instead of an answer -- the
# signup returns an empty body (curl does not follow redirects here), the token
# parse dies with a JSONDecodeError, and the probe then spends its whole run
# logging "HTTP 301" as if the app were broken. Refuse that input instead.
case "$BASE" in
  https://*|http://*) ;;
  *) echo "Base URL needs a scheme: use https://$BASE (or http://$BASE)" >&2; exit 2 ;;
esac

TOKEN=$(curl -fsS -X POST "$BASE/v1/auth/signup" -H 'content-type: application/json' \
  -d "{\"organization\":\"Rollout $STAMP\",\"name\":\"Probe\",\"email\":\"probe+$STAMP@example.com\",\"password\":\"Demo-Pass-2026\"}" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])' 2>/dev/null)

# Without this the probe runs its full duration against an empty token and
# reports a wall of 401s -- a long, confident, useless result.
if [[ -z "$TOKEN" ]]; then
  echo "Could not get a token from $BASE/v1/auth/signup -- not starting the probe." >&2
  echo "Check:  curl -i -X POST $BASE/v1/auth/signup -H 'content-type: application/json' \\" >&2
  echo "          -d '{\"organization\":\"t\",\"name\":\"t\",\"email\":\"t@example.com\",\"password\":\"Demo-Pass-2026\"}'" >&2
  exit 1
fi

ok=0; bad=0; pods=""
end=$((SECONDS + SECONDS_TO_RUN))
while (( SECONDS < end )); do
  out=$(curl -s -o /dev/null -D - -w '%{http_code}' --max-time 5 \
    "$BASE/v1/contacts" -H "authorization: Bearer $TOKEN")
  code="${out: -3}"
  pod=$(printf '%s' "$out" | tr -d '\r' | awk -F': ' 'tolower($1)=="x-served-by"{print $2}')
  if [[ "$code" == "200" ]]; then
    ok=$((ok + 1)); [[ -n "$pod" ]] && pods="$pods $pod"
  else
    bad=$((bad + 1)); echo "$(date +%T) ✗ HTTP $code"
  fi
  sleep 0.2
done
echo "Done: $ok OK, $bad failed."
echo "Pods that answered: $(printf '%s\n' $pods | sort -u | tr '\n' ' ')"
