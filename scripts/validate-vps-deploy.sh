#!/usr/bin/env bash
# A read-only preflight; does NOT pull images, publish a release or start containers.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${1:-$ROOT/deploy/vps/.env}"
COMPOSE="$ROOT/deploy/vps/compose.yaml"
command -v docker >/dev/null || { echo "Docker CLI is missing" >&2; exit 1; }
docker compose version >/dev/null || { echo "Docker Compose v2 is missing" >&2; exit 1; }
command -v jq >/dev/null || { echo "Install jq before running preflight" >&2; exit 1; }
[[ -r "$ENV_FILE" ]] || { echo "Missing deploy env file: $ENV_FILE" >&2; exit 1; }

config="$(docker compose --project-name limitcore --env-file "$ENV_FILE" -f "$COMPOSE" config --format json)"
image="$(jq -r '.services.api.image // ""' <<< "$config")"
if [[ ! "$image" =~ ^ghcr\.io/emanuelleda/limitcore@sha256:[a-f0-9]{64}$ ]]; then
  echo "Use a published GHCR image pinned to its real sha256 digest (not a tag)" >&2
  exit 1
fi
host="$(jq -r '.services.api.environment.REDIS_HOST // ""' <<< "$config")"
if [[ -z "$host" || "$host" == localhost || "$host" == 127.0.0.1 || "$host" == 0.0.0.0 || "$host" == *example* || "$host" == *REPLACE* ]]; then
  echo "External TLS Redis hostname is missing or still a placeholder" >&2
  exit 1
fi
if ! jq -e '
  .services.api.environment.SPRING_PROFILES_ACTIVE == "production" and
  .services.api.environment.REDIS_SSL_ENABLED == "true" and
  .services.api.environment.LIMITCORE_KEY_SCOPE == "tenant" and
  .services.api.read_only == true and
  (.services.api.ports | length == 1) and
  .services.api.ports[0].host_ip == "127.0.0.1" and
  (.services.api.secrets | length == 2)
' <<< "$config" >/dev/null; then
  echo "Unsafe compose configuration: production, TLS, tenant quota, read-only and loopback binding are required" >&2
  exit 1
fi

validate_file() {
  local label="$1" path="$2" minimum="$3" length mode uid gid
  [[ -f "$path" && -r "$path" ]] || { echo "$label file missing or unreadable by deploy user" >&2; exit 1; }
  mode="$(stat -c '%a' "$path")"
  uid="$(stat -c '%u' "$path")"
  gid="$(stat -c '%g' "$path")"
  local bits=$((8#$mode))
  if (( (bits & 0007) != 0 )); then
    echo "$label file must not grant access to other users" >&2
    exit 1
  fi
  if ! { [[ "$uid" == "10001" ]] && (( (bits & 0400) != 0 )); } &&
     ! { [[ "$gid" == "10001" ]] && (( (bits & 0040) != 0 )); }; then
    echo "$label file must be readable by container UID/GID 10001 (without world permissions)" >&2
    exit 1
  fi
  local secret
  secret="$(cat "$path")"
  length="${#secret}"
  if (( length < minimum )) || [[ "$secret" == *$'\n'* || "$secret" == *$'\r'* ]]; then
    echo "$label has invalid size or embedded newlines" >&2
    exit 1
  fi
}
tenants_file="$(jq -r '.secrets.tenants.file // ""' <<< "$config")"
redis_file="$(jq -r '.secrets.redis_password.file // ""' <<< "$config")"
validate_file "Tenant credentials" "$tenants_file" 34
validate_file "Redis password" "$redis_file" 16

# Validate tenant grammar, but never print sensitive credential contents.
tenants="$(cat "$tenants_file")"
IFS=',' read -ra entries <<< "$tenants"
declare -A tenant_seen=()
declare -A key_seen=()
for entry in "${entries[@]}"; do
  [[ "$entry" == *=* ]] || { echo "Tenant configuration must be tenant=secret" >&2; exit 1; }
  name="${entry%%=*}"
  keys="${entry#*=}"
  [[ "$name" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || { echo "Invalid tenant identifier" >&2; exit 1; }
  [[ -z "${tenant_seen[$name]+set}" ]] || { echo "Duplicate tenant" >&2; exit 1; }
  tenant_seen["$name"]=1
  IFS='|' read -ra credentials <<< "$keys"
  if (( ${#credentials[@]} < 1 || ${#credentials[@]} > 2 )); then
    echo "Each tenant must have one or two credentials" >&2
    exit 1
  fi
  for credential in "${credentials[@]}"; do
    if (( ${#credential} < 32 || ${#credential} > 256 )) || [[ ! "$credential" =~ ^[A-Za-z0-9_-]+$ ]]; then
      echo "Tenant credentials must be 32-256 bytes of URL-safe ASCII" >&2
      exit 1
    fi
    [[ -z "${key_seen[$credential]+set}" ]] || { echo "Duplicate tenant credential" >&2; exit 1; }
    key_seen["$credential"]=1
  done
done
echo "PASS: immutable image digest, loopback binding, TLS Redis, least-privilege settings and secret files."
echo "NOTE: this check does not prove Redis connectivity, certificate trust, HA, backups, HTTPS or load capacity."
