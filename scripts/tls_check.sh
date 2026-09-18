#!/usr/bin/env bash
#
# tls_check.sh -- verify HTTPS end to end, and produce evidence.
#
#   scripts/tls_check.sh drakkar.nordheim.online
#   scripts/tls_check.sh drakkar.nordheim.online | tee docs/results/tls-check.txt
#
# Exits non-zero if any check fails. Read-only: touches nothing in the cluster.

set -uo pipefail

HOST="${1:-${HOST:-drakkar.nordheim.online}}"
NS="${NS:-drakkar}"

bold=$'\033[1m'; red=$'\033[31m'; green=$'\033[32m'; yellow=$'\033[33m'; off=$'\033[0m'
fails=0
pass() { printf '  %s[pass]%s %s\n' "$green"  "$off" "$1"; }
fail() { printf '  %s[FAIL]%s %s\n' "$red"    "$off" "$1"; fails=$((fails+1)); }
skip() { printf '  %s[skip]%s %s\n' "$yellow" "$off" "$1"; }
head_() { printf '\n%s%s%s\n' "$bold" "$1" "$off"; }

printf '%sTLS check -- %s -- %s%s\n' "$bold" "$HOST" "$(date -Is)" "$off"

# ------------------------------------------------------------------ the chain
head_ "Certificate"

leaf="$(echo | openssl s_client -connect "$HOST:443" -servername "$HOST" 2>/dev/null \
        | openssl x509 2>/dev/null)"

if [ -z "$leaf" ]; then
  fail "could not retrieve a certificate from $HOST:443"
  printf '\n%s%d check(s) failed.%s Nothing below can run without a certificate.\n' "$red$bold" "$fails" "$off"
  exit 1
fi

issuer="$(printf '%s' "$leaf" | openssl x509 -noout -issuer 2>/dev/null)"
printf '  %s\n' "$issuer"
case "$issuer" in
  *"Let's Encrypt"*|*"(STAGING)"*) pass "issued by Let's Encrypt" ;;
  *) fail "issuer is not Let's Encrypt" ;;
esac
case "$issuer" in
  *"(STAGING)"*) fail "this is a STAGING certificate -- browsers will not trust it. Delete secret/drakkar-tls and re-run enable_tls.sh without STAGING=1" ;;
esac

sans="$(printf '%s' "$leaf" | openssl x509 -noout -ext subjectAltName 2>/dev/null | tr -d ' ')"
if printf '%s' "$sans" | grep -q "DNS:$HOST\(,\|$\)"; then
  pass "$HOST is in the SANs"
else
  fail "$HOST is NOT in the SANs: $sans"
fi

notafter="$(printf '%s' "$leaf" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)"
end_s="$(date -d "$notafter" +%s 2>/dev/null || echo 0)"
now_s="$(date +%s)"
days=$(( (end_s - now_s) / 86400 ))
if [ "$end_s" -gt 0 ] && [ "$days" -gt 0 ]; then
  pass "valid for $days more days (expires $notafter)"
else
  fail "expired or unreadable expiry date: $notafter"
fi

# ------------------------------------------------------------------- the path
head_ "Trust and routing"

if curl -sS -o /dev/null --max-time 15 "https://$HOST/"; then
  pass "curl trusts the chain without -k"
else
  fail "curl will not trust https://$HOST/ -- incomplete chain, or a staging certificate"
fi

redir="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "http://$HOST/" || echo 000)"
if [ "$redir" = "301" ]; then
  pass "http:// returns 301"
else
  fail "http:// returned $redir, expected 301"
fi

web="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "https://$HOST/" || echo 000)"
[ "$web" = "200" ] && pass "web client answers 200 over TLS" || fail "web client returned $web over TLS"

# /v1/auth/me, not /healthz. The API's own /healthz and /readyz sit at the root
# of the API service, but the Gateway routes / to the WEB service and only /v1
# to the API -- so the health endpoints are reachable by the kubelet probes on
# the pod port, and deliberately not through the load balancer.
#
# An unauthenticated GET of /v1/auth/me is SUPPOSED to return 401. That is the
# strongest single signal available here: the request terminated TLS at the
# Gateway, matched the /v1 prefix, reached the API container, and was processed
# by its auth middleware. A 401 is the API working, not the API failing.
api="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "https://$HOST/v1/auth/me" || echo 000)"
case "$api" in
  401|403) pass "API answers $api at /v1/auth/me over TLS (expected: unauthenticated)" ;;
  200)     pass "API answers 200 at /v1/auth/me over TLS (a session cookie was sent)" ;;
  000)     fail "API did not answer at all over TLS -- no response before timeout" ;;
  5*)      fail "API returned $api over TLS -- the route works, the service is unhealthy" ;;
  *)       fail "API returned $api over TLS, expected 401" ;;
esac

# --------------------------------------------------------------- TLS versions
head_ "Protocol versions"

for v in "tls1_2:TLS 1.2" "tls1_3:TLS 1.3"; do
  flag="${v%%:*}"; label="${v##*:}"
  if echo | openssl s_client -connect "$HOST:443" -servername "$HOST" "-$flag" >/dev/null 2>&1; then
    pass "$label accepted"
  else
    fail "$label rejected -- expected it to be accepted"
  fi
done

if echo | openssl s_client -connect "$HOST:443" -servername "$HOST" -tls1_1 >/dev/null 2>&1; then
  fail "TLS 1.1 accepted -- it should be refused"
else
  pass "TLS 1.1 refused"
fi

# ------------------------------------------------------------- cluster state
head_ "Cluster state"

if command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
  ready="$(kubectl -n "$NS" get certificate drakkar-tls \
           -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
  [ "$ready" = "True" ] && pass "Certificate drakkar-tls is Ready" \
                        || fail "Certificate drakkar-tls Ready=${ready:-<not found>}"

  stuck="$(kubectl -n "$NS" get challenge --no-headers 2>/dev/null | wc -l)"
  [ "$stuck" -eq 0 ] && pass "no ACME challenges pending" \
                     || fail "$stuck ACME challenge(s) still pending -- kubectl -n $NS describe challenge"

  prog="$(kubectl -n "$NS" get gateway drakkar \
          -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || true)"
  [ "$prog" = "True" ] && pass "Gateway is Programmed" \
                       || fail "Gateway Programmed=${prog:-<not found>}"
else
  skip "kubectl unavailable -- cluster-side checks not run"
fi

# --------------------------------------------------------------------- result
printf '\n'
if [ "$fails" -eq 0 ]; then
  printf '%sAll checks passed.%s\n' "$green$bold" "$off"
  printf 'Now open https://%s, click the padlock, and screenshot the certificate.\n\n' "$HOST"
  exit 0
else
  printf '%s%d check(s) failed.%s See 04_HTTPS_SETUP.md §6.\n\n' "$red$bold" "$fails" "$off"
  exit 1
fi
