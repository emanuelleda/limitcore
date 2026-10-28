#!/usr/bin/env bash
set -Eeuo pipefail

export LIMITCORE_API_KEY="ci-smoke-key-very-long-and-not-for-production"
REDIS_CONTAINER="limitcore-redis-smoke"
APP_LOG="$(mktemp)"
PREFLIGHT_LOG="$(mktemp)"

cleanup() {
  if [[ -n "${APP_PID:-}" ]]; then kill "$APP_PID" 2>/dev/null || true; fi
  docker rm -f "$REDIS_CONTAINER" >/dev/null 2>&1 || true
  rm -f "$APP_LOG" "$PREFLIGHT_LOG"
}
trap cleanup EXIT

docker run -d --name "$REDIS_CONTAINER" -p 127.0.0.1:6379:6379 redis:7.4-alpine
echo "Verifying production profile rejects plaintext Redis"
if env SPRING_PROFILES_ACTIVE=production REDIS_SSL_ENABLED=false \
  LIMITCORE_API_KEY="$LIMITCORE_API_KEY" timeout 30s \
  java -jar target/limitcore-0.1.0-SNAPSHOT.jar >"$PREFLIGHT_LOG" 2>&1; then
  echo "Production profile incorrectly started with Redis TLS disabled"
  exit 1
fi
if ! grep -q "Production Redis connections must use TLS" "$PREFLIGHT_LOG"; then
  echo "Production profile failed for an unexpected reason"
  tail -80 "$PREFLIGHT_LOG"
  exit 1
fi

java -jar target/limitcore-0.1.0-SNAPSHOT.jar >"$APP_LOG" 2>&1 &
APP_PID=$!

for attempt in {1..45}; do
  if curl --silent --fail --max-time 2 http://127.0.0.1:8080/actuator/health/readiness | grep -q '"UP"'; then
    break
  fi
  if [[ "$attempt" == 45 ]]; then
    echo "API did not become healthy"
    cat "$APP_LOG"
    exit 1
  fi
  sleep 2
done

echo "Running API k6 smoke checks"
docker run --rm --network host \
  -v "$PWD/benchmarks:/scripts:ro" \
  -e "LIMITCORE_API_KEY=$LIMITCORE_API_KEY" \
  -e "LIMITCORE_URL=http://127.0.0.1:8080/v1/limits/check" \
  grafana/k6:0.54.0 run /scripts/smoke.js

request_status() {
  curl --silent --output /dev/null --max-time 5 \
    --write-out '%{http_code}' \
    -X POST http://127.0.0.1:8080/v1/limits/check \
    -H "X-API-Key: $LIMITCORE_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"key":"failure-injection"}' || true
}

echo "Verifying bounded requests and authentication"
unauthorized_status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
    -X POST http://127.0.0.1:8080/v1/limits/check \
    -H "Content-Type: application/json" \
    -d '{"key":"unauthorized"}')"
if [[ "$unauthorized_status" != 401 ]]; then
  echo "Expected 401 for missing API credentials; got $unauthorized_status"
  exit 1
fi
status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
    -X POST http://127.0.0.1:8080/v1/limits/check \
    -H "X-API-Key: $LIMITCORE_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\\\"key\\\":\\\"$(printf 'x%.0s' {1..1100})\\\"}")"
if [[ "$status" != 413 ]]; then
  echo "Expected 413 for an oversized request; got $status"
  exit 1
fi

echo "Simulating Redis outage"
docker stop --time 1 "$REDIS_CONTAINER"
status="$(request_status)"
if [[ "$status" != 503 && "$status" != 000 ]]; then
  echo "Expected HTTP 503 or transport timeout while Redis unavailable; got $status"
  exit 1
fi
ready_status="$(curl --silent --output /dev/null --max-time 5 --write-out '%{http_code}' \
    http://127.0.0.1:8080/actuator/health/readiness || true)"
if [[ "$ready_status" != 503 && "$ready_status" != 000 ]]; then
  echo "Expected readiness to fail while Redis is offline; got $ready_status"
  exit 1
fi

echo "Recovering Redis and verifying API can decide again"
docker start "$REDIS_CONTAINER"
for attempt in {1..25}; do
  status="$(request_status)"
  ready_status="$(curl --silent --output /dev/null --max-time 5 --write-out '%{http_code}' http://127.0.0.1:8080/actuator/health/readiness || true)"
  if [[ "$status" == 200 && "$ready_status" == 200 ]]; then
    echo "Redis outage, readiness, and recovery smoke checks passed"
    exit 0
  fi
  sleep 2
done
echo "API did not recover after Redis restart; last HTTP status: $status"
tail -100 "$APP_LOG"
exit 1
