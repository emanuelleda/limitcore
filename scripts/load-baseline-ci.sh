#!/usr/bin/env bash
# Reproducible single-runner LOAD BASELINE, not a production capacity certification.
set -Eeuo pipefail
REDIS_CONTAINER="limitcore-load-baseline-redis"
OUTPUT_DIR="$PWD/target/load-baseline"
LOG_FILE="$(mktemp)"
APP_PID=""
cleanup() {
  if [[ -n "$APP_PID" ]]; then kill "$APP_PID" 2>/dev/null || true; fi
  docker rm -f "$REDIS_CONTAINER" >/dev/null 2>&1 || true
  rm -f "$LOG_FILE"
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR"
# k6 runs as the current runner UID, so the artifact directory stays private.
export LIMITCORE_API_KEY="ci-load-baseline-not-a-production-credential"
export LIMITCORE_ALGORITHM="${LIMITCORE_ALGORITHM:-token-bucket}"
export LIMITCORE_CAPACITY=5000
export LIMITCORE_WINDOW_SECONDS=60
export LIMITCORE_MAX_ACTIVE_KEYS=1000
export LIMITCORE_KEY_SCOPE=identifier
export REDIS_HOST=127.0.0.1
export REDIS_PORT=6389

docker run -d --name "$REDIS_CONTAINER" -p 127.0.0.1:6389:6379 \
  redis:7.4-alpine >/dev/null

for attempt in {1..30}; do
  if docker exec "$REDIS_CONTAINER" redis-cli ping 2>/dev/null | grep -qx PONG; then
    break
  fi
  if [[ "$attempt" -eq 30 ]]; then
    docker logs "$REDIS_CONTAINER"
    exit 1
  fi
  sleep 1
done

java -jar target/limitcore-0.1.0-SNAPSHOT.jar >"$LOG_FILE" 2>&1 &
APP_PID=$!

for attempt in {1..45}; do
  if curl --silent --fail --max-time 3 \
      http://127.0.0.1:8080/actuator/health/readiness | grep -q '"UP"'; then
    break
  fi
  if [[ "$attempt" -eq 45 ]]; then
    cat "$LOG_FILE"
    exit 1
  fi
  sleep 2
done

# Deliberately bounded, repeatable runner-level smoke load; tune independently
# for staging capacity testing. HTTP 200/allowed=false is a valid quota response.
export LIMITCORE_BENCH_VUS=20
export LIMITCORE_BENCH_DURATION=30s
export LIMITCORE_BENCH_KEYS=100
export LIMITCORE_BENCH_P95_MS=1000

set +e
docker run --rm --network host \
  --user "$(id -u):$(id -g)" \
  -v "$PWD/benchmarks:/scripts:ro" \
  -v "$OUTPUT_DIR:/reports" \
  -e "LIMITCORE_URL=http://127.0.0.1:8080/v1/limits/check" \
  -e "LIMITCORE_API_KEY=$LIMITCORE_API_KEY" \
  -e "LIMITCORE_BENCH_VUS=$LIMITCORE_BENCH_VUS" \
  -e "LIMITCORE_BENCH_DURATION=$LIMITCORE_BENCH_DURATION" \
  -e "LIMITCORE_BENCH_KEYS=$LIMITCORE_BENCH_KEYS" \
  -e "LIMITCORE_BENCH_P95_MS=$LIMITCORE_BENCH_P95_MS" \
  grafana/k6:0.54.0 run --summary-export=/reports/k6-summary.json \
  /scripts/k6.js >"$OUTPUT_DIR/k6-console.log" 2>&1
result=$?
set -e

jq -n \
  --arg sha "${GITHUB_SHA:-local}" \
  --arg algorithm "$LIMITCORE_ALGORITHM" \
  --arg vus "$LIMITCORE_BENCH_VUS" \
  --arg duration "$LIMITCORE_BENCH_DURATION" \
  --arg keys "$LIMITCORE_BENCH_KEYS" \
  --arg p95Limit "$LIMITCORE_BENCH_P95_MS" \
  --arg runner "GitHub Actions ubuntu-latest single runner" \
  --arg redisVersion "$(docker exec "$REDIS_CONTAINER" redis-server --version)" \
  '{sha:$sha, environment:$runner, topology:"single API process + single local Redis", redisVersion:$redisVersion, algorithm:$algorithm, vus:($vus|tonumber), duration:$duration, distinctKeys:($keys|tonumber), p95LimitMs:($p95Limit|tonumber), verdict:"CI regression baseline only, not production capacity or multi-AZ SLO"}' \
  > "$OUTPUT_DIR/configuration.json"

if [[ ! -s "$OUTPUT_DIR/k6-summary.json" ]]; then
  echo "Missing machine-readable k6 evidence"
  cat "$OUTPUT_DIR/k6-console.log"
  exit 1
fi

jq -e '
  (.metrics.http_reqs.count > 0)
  and (.metrics.http_req_duration["p(95)"] >= 0)
  and (.metrics.http_req_duration["p(99)"] >= 0)
' "$OUTPUT_DIR/k6-summary.json" >/dev/null

jq -r '
  "HTTP requests: \(.metrics.http_reqs.count)",
  "Request rate: \(.metrics.http_reqs.rate) req/s",
  "p95: \(.metrics.http_req_duration["p(95)"]) ms",
  "p99: \(.metrics.http_req_duration["p(99)"]) ms"
' "$OUTPUT_DIR/k6-summary.json"

if [[ "$result" -ne 0 ]]; then
  echo "k6 thresholds failed (exit $result); preserving evidence artifacts"
  tail -100 "$OUTPUT_DIR/k6-console.log"
  exit "$result"
fi
echo "Bounded CI load baseline passed; do not extrapolate to production"
