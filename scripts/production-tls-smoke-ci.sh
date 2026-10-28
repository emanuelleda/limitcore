#!/usr/bin/env bash
# Isolated CI lab: production Spring profile + Redis TLS + Redis password.
set -Eeuo pipefail

WORKDIR="$(mktemp -d)"
REDIS_CONTAINER="limitcore-redis-tls-ci"
APP_PID=""
cleanup() {
  if [[ -n "$APP_PID" ]]; then kill "$APP_PID" 2>/dev/null || true; fi
  docker rm -f "$REDIS_CONTAINER" >/dev/null 2>&1 || true
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

# All secrets and certificates below are disposable CI fixtures, never production data.
export REDIS_PASSWORD="ci-only-redis-password-long-random-fixture"
export LIMITCORE_API_KEY=""
export LIMITCORE_TENANTS="alpha=ci-alpha-tenant-secret-long-enough-123,beta=ci-beta-tenant-secret-long-enough-456"
export LIMITCORE_TENANT_CAPACITIES="alpha=2,beta=2"
export LIMITCORE_ALGORITHM=fixed-window
export LIMITCORE_CAPACITY=10
export LIMITCORE_WINDOW_SECONDS=3600
export SPRING_PROFILES_ACTIVE=production
export REDIS_SSL_ENABLED=true
export REDIS_HOST=localhost
export REDIS_PORT=6387
export LIMITCORE_TRACING_SAMPLE_RATE=0

openssl req -x509 -newkey rsa:2048 -nodes -days 1 -sha256 \
  -keyout "$WORKDIR/ca.key" -out "$WORKDIR/ca.crt" \
  -subj "/CN=LimitCore CI Root CA" >/dev/null 2>&1
openssl req -new -newkey rsa:2048 -nodes \
  -keyout "$WORKDIR/server.key" -out "$WORKDIR/server.csr" \
  -subj "/CN=localhost" >/dev/null 2>&1
printf 'subjectAltName=DNS:localhost,IP:127.0.0.1\nextendedKeyUsage=serverAuth\n' > "$WORKDIR/server.ext"
openssl x509 -req -in "$WORKDIR/server.csr" -CA "$WORKDIR/ca.crt" \
  -CAkey "$WORKDIR/ca.key" -CAcreateserial -out "$WORKDIR/server.crt" \
  -days 1 -sha256 -extfile "$WORKDIR/server.ext" >/dev/null 2>&1

keytool -importcert -noprompt -alias limitcore-ci-ca -file "$WORKDIR/ca.crt" \
  -keystore "$WORKDIR/truststore.p12" -storetype PKCS12 \
  -storepass changeit >/dev/null 2>&1

# Docker Redis uses an unprivileged UID; this temporary directory contains only CI fixtures.
chmod 755 "$WORKDIR"
chmod 644 "$WORKDIR"/server.key "$WORKDIR"/server.crt "$WORKDIR"/ca.crt

docker run -d --name "$REDIS_CONTAINER" -p 127.0.0.1:6387:6387 \
  -v "$WORKDIR:/certs:ro" redis:7.4-alpine \
  redis-server --port 0 --tls-port 6387 \
  --tls-cert-file /certs/server.crt --tls-key-file /certs/server.key \
  --tls-ca-cert-file /certs/ca.crt --tls-auth-clients no \
  --requirepass "$REDIS_PASSWORD" >/dev/null

for attempt in {1..30}; do
  if docker exec -e "REDISCLI_AUTH=$REDIS_PASSWORD" "$REDIS_CONTAINER" \
    redis-cli --tls --cacert /certs/ca.crt -p 6387 ping 2>/dev/null | grep -qx PONG; then
    break
  fi
  if [[ "$attempt" == 30 ]]; then
    echo "Redis TLS fixture did not start"
    docker logs "$REDIS_CONTAINER"
    exit 1
  fi
  sleep 1
done

java -Djavax.net.ssl.trustStore="$WORKDIR/truststore.p12" \
  -Djavax.net.ssl.trustStorePassword=changeit \
  -jar target/limitcore-0.1.0-SNAPSHOT.jar >"$WORKDIR/api.log" 2>&1 &
APP_PID=$!

for attempt in {1..50}; do
  if curl -fsS --max-time 3 http://127.0.0.1:8080/actuator/health/readiness \
      | grep -q '"UP"'; then
    break
  fi
  if [[ "$attempt" == 50 ]]; then
    echo "Production profile did not become healthy with authenticated TLS Redis"
    tail -100 "$WORKDIR/api.log"
    exit 1
  fi
  sleep 2
done

post() {
  local secret="$1" key="$2"
  curl --silent --show-error --max-time 8 \
    -X POST http://127.0.0.1:8080/v1/limits/check \
    -H "X-API-Key: $secret" -H "Content-Type: application/json" \
    -d "{\"key\":\"$key\"}"
}

ALPHA="ci-alpha-tenant-secret-long-enough-123"
BETA="ci-beta-tenant-secret-long-enough-456"
for key in first second; do
  post "$ALPHA" "$key" | jq -e '.allowed == true' >/dev/null || {
    echo "Expected tenant alpha to allow first two distinct identifiers"; exit 1;
  }
done
post "$ALPHA" third | jq -e '.allowed == false' >/dev/null || {
  echo "Tenant alpha bypassed its global quota by changing identifier"; exit 1;
}
post "$BETA" different | jq -e '.allowed == true' >/dev/null || {
  echo "Tenant beta was incorrectly charged for alpha's requests"; exit 1;
}
unauthorized="$(curl --silent --output /dev/null --write-out '%{http_code}' \
  -X POST http://127.0.0.1:8080/v1/limits/check \
  -H 'X-API-Key: wrong' -H 'Content-Type: application/json' \
  -d '{"key":"invalid"}')"
test "$unauthorized" = 401

echo "Simulating unavailable authenticated TLS Redis"
docker stop --time 1 "$REDIS_CONTAINER" >/dev/null
status="$(curl --silent --output /dev/null --max-time 8 --write-out '%{http_code}' \
  -X POST http://127.0.0.1:8080/v1/limits/check \
  -H "X-API-Key: $BETA" -H 'Content-Type: application/json' \
  -d '{"key":"redis-outage"}' || true)"
if [[ "$status" != 503 && "$status" != 000 ]]; then
  echo "Expected 503/transport failure on authenticated Redis outage, got $status"
  exit 1
fi

docker start "$REDIS_CONTAINER" >/dev/null
recovered=false
for attempt in {1..35}; do
  if curl -fsS --max-time 3 http://127.0.0.1:8080/actuator/health/readiness \
      | grep -q '"UP"'; then
    if post "$BETA" recovered 2>/dev/null | jq -e '.allowed == true' >/dev/null; then
      recovered=true
      break
    fi
  fi
  sleep 2
done
if [[ "$recovered" != true ]]; then
  echo "Production profile did not recover after authenticated TLS Redis restart"
  tail -100 "$WORKDIR/api.log"
  exit 1
fi
echo "Production Redis TLS, authentication, tenant quotas and fail-closed recovery passed"
