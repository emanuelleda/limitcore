#!/usr/bin/env bash
# CI-only smoke for deployment configuration. No image is pulled or launched.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
command -v openssl >/dev/null
command -v sudo >/dev/null

printf 'ci=%s' "$(openssl rand -hex 32)" >"$TMP/tenants"
printf '%s' 'ci-only-redis-password-not-a-real-secret' >"$TMP/redis-password"
sudo chgrp 10001 "$TMP/tenants" "$TMP/redis-password"
chmod 640 "$TMP/tenants" "$TMP/redis-password"

printf -v digest '%064d' 0
cat >"$TMP/deploy.env" <<EOF
LIMITCORE_IMAGE=ghcr.io/emanuelleda/limitcore@sha256:$digest
LIMITCORE_REDIS_HOST=redis.staging.internal
LIMITCORE_REDIS_PORT=6380
LIMITCORE_REDIS_USERNAME=default
LIMITCORE_TENANTS_FILE=$TMP/tenants
LIMITCORE_REDIS_PASSWORD_FILE=$TMP/redis-password
LIMITCORE_LOCAL_PORT=18080
EOF
bash "$ROOT/scripts/validate-vps-deploy.sh" "$TMP/deploy.env" >/dev/null
must_fail() {
  if bash "$ROOT/scripts/validate-vps-deploy.sh" "$TMP/deploy.env" >/dev/null 2>&1; then
    echo "Deployment preflight accepted an unsafe configuration" >&2
    exit 1
  fi
}
sed -i "s|^LIMITCORE_IMAGE=.*|LIMITCORE_IMAGE=ghcr.io/emanuelleda/limitcore:latest|" "$TMP/deploy.env"
must_fail
sed -i "s|^LIMITCORE_IMAGE=.*|LIMITCORE_IMAGE=ghcr.io/emanuelleda/limitcore@sha256:$digest|" "$TMP/deploy.env"
sed -i 's|^LIMITCORE_REDIS_HOST=.*|LIMITCORE_REDIS_HOST=localhost|' "$TMP/deploy.env"
must_fail
sed -i 's|^LIMITCORE_REDIS_HOST=.*|LIMITCORE_REDIS_HOST=redis.staging.internal|' "$TMP/deploy.env"
chmod 644 "$TMP/tenants"
must_fail
chmod 640 "$TMP/tenants"
mv "$TMP/redis-password" "$TMP/redis-password-old"
must_fail
mv "$TMP/redis-password-old" "$TMP/redis-password"
bash "$ROOT/scripts/validate-vps-deploy.sh" "$TMP/deploy.env" >/dev/null
echo "VPS deployment preflight passed (positive and four fail-closed checks)."
