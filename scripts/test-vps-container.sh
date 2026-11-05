#!/usr/bin/env bash
# CI only: boot the ACTUAL image through VPS compose using disposable secrets.
# Intentionally no Redis: readiness and authenticated decisions must fail closed.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
cleanup() {
  docker compose -p limitcore-ci-compose --env-file "$TMP/deploy.env" -f "$ROOT/deploy/vps/compose.yaml" -f "$TMP/override.yaml" down --remove-orphans >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT
command -v docker >/dev/null
command -v curl >/dev/null
command -v jq >/dev/null

printf '%s' 'staging=ci-staging-tenant-secret-long-enough-1234567890' >"$TMP/tenants"
printf '%s' 'ci-redis-password-not-a-real-secret-1234' >"$TMP/redis-password"
sudo chgrp 10001 "$TMP/tenants" "$TMP/redis-password"
chmod 640 "$TMP/tenants" "$TMP/redis-password"
printf -v digest '%064d' 0
cat >"$TMP/deploy.env" <<EOF
LIMITCORE_IMAGE=ghcr.io/emanuelleda/limitcore@sha256:$digest
LIMITCORE_REDIS_HOST=redis.invalid
LIMITCORE_REDIS_PORT=6380
LIMITCORE_TENANTS_FILE=$TMP/tenants
LIMITCORE_REDIS_PASSWORD_FILE=$TMP/redis-password
LIMITCORE_LOCAL_PORT=18081
EOF
cat >"$TMP/override.yaml" <<'YAML'
services:
  api:
    image: limitcore:ci
YAML
compose=(docker compose -p limitcore-ci-compose --env-file "$TMP/deploy.env"
  -f "$ROOT/deploy/vps/compose.yaml" -f "$TMP/override.yaml")
"${compose[@]}" up -d --no-build >/dev/null

ready=false
for attempt in {1..60}; do
  if curl --silent --fail --max-time 2 http://127.0.0.1:18081/actuator/health/liveness | jq -e '.status == "UP"' >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 2
done
if [[ "$ready" != "true" ]]; then
  echo "Image did not boot with secret-backed Compose entrypoint" >&2
  exit 1
fi
echo "PASS: runtime booted as non-root with file-backed secrets"
status="$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' http://127.0.0.1:18081/actuator/health/readiness || true)"
[[ "$status" == 503 ]] || { echo "Expected readiness 503 when external Redis is unavailable, got $status" >&2; exit 1; }
status="$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:18081/v1/limits/check \
  -H 'X-API-Key: invalid-ci-credential' -H 'Content-Type: application/json' -d '{"key":"ci"}' || true)"
[[ "$status" == 401 ]] || { echo "Expected invalid credential 401, got $status" >&2; exit 1; }
status="$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:18081/v1/limits/check \
  -H 'X-API-Key: ci-staging-tenant-secret-long-enough-1234567890' -H 'Content-Type: application/json' \
  -d '{"key":"ci"}' || true)"
[[ "$status" == 503 ]] || { echo "Expected authenticated decision to fail closed with 503, got $status" >&2; exit 1; }
echo "PASS: liveness UP, readiness DOWN, 401 invalid credentials, and 503 fail-closed without Redis"
