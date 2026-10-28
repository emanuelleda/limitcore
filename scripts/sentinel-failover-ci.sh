#!/usr/bin/env bash
# High-availability lab: one primary, one replica, three Sentinel voters.
# Requires Linux Docker host-network mode (GitHub ubuntu-latest).
set -Eeuo pipefail

export LIMITCORE_API_KEY="sentinel-ci-secret-not-for-production"
export SPRING_DATA_REDIS_SENTINEL_MASTER="limitcore-master"
export SPRING_DATA_REDIS_SENTINEL_NODES="127.0.0.1:26379,127.0.0.1:26380,127.0.0.1:26381"
export REDIS_CONNECT_TIMEOUT="2s"
export REDIS_COMMAND_TIMEOUT="2s"

WORKDIR="$(mktemp -d)"
APP_PID=""
cleanup() {
  if [[ -n "$APP_PID" ]]; then kill "$APP_PID" 2>/dev/null || true; fi
  for name in lc-master lc-replica lc-sentinel-26379 lc-sentinel-26380 lc-sentinel-26381; do
    docker rm -f "$name" >/dev/null 2>&1 || true
  done
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

docker run -d --name lc-master --network host redis:7.4-alpine \
  redis-server --port 6380 --bind 127.0.0.1 --protected-mode no --save "" --appendonly no

docker run -d --name lc-replica --network host redis:7.4-alpine \
  redis-server --port 6381 --bind 127.0.0.1 --protected-mode no --save "" --appendonly no \
  --replicaof 127.0.0.1 6380

for attempt in {1..30}; do
  if docker exec lc-replica redis-cli -p 6381 INFO replication | grep -q 'master_link_status:up'; then
    break
  fi
  if [[ "$attempt" -eq 30 ]]; then
    echo "Replica failed to connect to initial master"
    docker logs lc-replica
    exit 1
  fi
  sleep 1
done

for port in 26379 26380 26381; do
  cat > "$WORKDIR/sentinel-$port.conf" <<EOF
port $port
bind 127.0.0.1
protected-mode no
sentinel monitor limitcore-master 127.0.0.1 6380 2
sentinel down-after-milliseconds limitcore-master 2000
sentinel failover-timeout limitcore-master 10000
sentinel parallel-syncs limitcore-master 1
EOF
  docker run -d --name "lc-sentinel-$port" --network host \
    -v "$WORKDIR/sentinel-$port.conf:/config/sentinel.conf:ro" \
    redis:7.4-alpine sh -c \
      'cp /config/sentinel.conf /tmp/sentinel.conf && exec redis-server /tmp/sentinel.conf --sentinel'
done

sleep 5
java -jar target/limitcore-0.1.0-SNAPSHOT.jar > "$WORKDIR/api.log" 2>&1 &
APP_PID=$!

get_status() {
  curl --silent --output /dev/null --max-time 6 --write-out '%{http_code}' \
    -X POST http://127.0.0.1:8080/v1/limits/check \
    -H "X-API-Key: $LIMITCORE_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"key":"sentinel-lab"}' || true
}

initial_ok=false
for attempt in {1..40}; do
  if [[ "$(get_status)" == 200 ]]; then initial_ok=true; break; fi
  sleep 2
done
if [[ "$initial_ok" != true ]]; then
  echo "API failed to start with Sentinel"
  tail -100 "$WORKDIR/api.log"
  for port in 26379 26380 26381; do docker logs "lc-sentinel-$port" | tail -30; done
  exit 1
fi

echo "Failing Redis primary on 6380..."
docker stop --time 1 lc-master

promoted=false
for attempt in {1..90}; do
  port="$(docker exec lc-sentinel-26379 redis-cli -p 26379 --raw \
    SENTINEL get-master-addr-by-name limitcore-master | tail -n 1 | tr -d '\r' || true)"
  if [[ "$port" == 6381 ]]; then
    promoted=true
    break
  fi
  sleep 1
done
if [[ "$promoted" != true ]]; then
  echo "Sentinel failed to promote Redis replica"
  for port in 26379 26380 26381; do docker logs "lc-sentinel-$port" | tail -40; done
  exit 1
fi

echo "Sentinel elected replica on 6381; validating client recovery..."
recovered=false
for attempt in {1..45}; do
  if [[ "$(get_status)" == 200 ]]; then recovered=true; break; fi
  sleep 2
done
if [[ "$recovered" != true ]]; then
  echo "API did not recover after Redis primary promotion"
  tail -120 "$WORKDIR/api.log"
  exit 1
fi

role="$(docker exec lc-replica redis-cli -p 6381 --raw ROLE | head -n 1 | tr -d '\r')"
if [[ "$role" != master ]]; then
  echo "Promoted node is not the new master: $role"
  exit 1
fi
echo "Redis Sentinel promotion and API reconnection passed"
