#!/usr/bin/env bash
# Non-destructive smoke for a TLS-enabled STAGING deployment only.
# Performs one allowed/denied decision and an invalid-credential check.
set -Eeuo pipefail
: "${LIMITCORE_STAGING_URL:?Set the HTTPS base URL of the staging instance}"
: "${LIMITCORE_API_KEY:?Read staging API key from a secret manager}"
: "${LIMITCORE_STAGING_ACK:?Set LIMITCORE_STAGING_ACK=staging-only after verifying target}"
if [[ "$LIMITCORE_STAGING_ACK" != "staging-only" ]]; then
  echo "Explicit staging acknowledgement required" >&2
  exit 1
fi
command -v curl >/dev/null
command -v jq >/dev/null
url="${LIMITCORE_STAGING_URL%/}"
if [[ "$url" != https://* || "$url" == *'?'* || "$url" == *'#'* ]]; then
  echo "Only an HTTPS base URL without query/fragment is supported" >&2
  exit 1
fi
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
check_status() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $label expected HTTP $expected, got $actual" >&2
    exit 1
  fi
  echo "PASS: $label HTTP $expected"
}
liveness="$(curl --silent --show-error --connect-timeout 5 --max-time 15 -o "$tmp/live.json" -w '%{http_code}' "$url/actuator/health/liveness")"
check_status liveness 200 "$liveness"
readiness="$(curl --silent --show-error --connect-timeout 5 --max-time 15 -o "$tmp/ready.json" -w '%{http_code}' "$url/actuator/health/readiness")"
check_status readiness 200 "$readiness"

status="$(curl --silent --show-error --connect-timeout 5 --max-time 15 -o "$tmp/decision.json" -w '%{http_code}' \
  -X POST "$url/v1/limits/check" \
  -H 'Content-Type: application/json' \
  -H "X-API-Key: $LIMITCORE_API_KEY" \
  --data '{"key":"staging-preflight"}')"
check_status "quota decision" 200 "$status"
jq -e '(.allowed | type) == "boolean" and (.algorithm | type) == "string"' "$tmp/decision.json" >/dev/null || {
  echo "FAIL: unexpected decision schema" >&2
  exit 1
}
echo "PASS: decision schema"

status="$(curl --silent --show-error --connect-timeout 5 --max-time 15 -o "$tmp/denied.json" -w '%{http_code}' \
  -X POST "$url/v1/limits/check" \
  -H 'Content-Type: application/json' \
  -H 'X-API-Key: invalid-staging-preflight-credential' \
  --data '{"key":"staging-preflight"}')"
check_status "invalid credential rejected" 401 "$status"
echo "Staging smoke passed. This does not prove HA, backups, load capacity or rollback."
