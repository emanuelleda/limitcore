#!/usr/bin/env bash
# Starts a disposable Codespaces preview; never enables the production profile.
set -Eeuo pipefail
cd /workspaces/limitcore
state="$HOME/.local/state/limitcore-demo"
mkdir -p "$state"
chmod 700 "$state"
keyfile="$state/api-key"
pidfile="$state/app.pid"
logfile="$state/app.log"
if [[ ! -s "$keyfile" ]]; then
  umask 077
  head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$keyfile"
fi
chmod 600 "$keyfile"

if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
  echo "LimitCore preview process already running."
  exit 0
fi
if curl -fsS --connect-timeout 2 --max-time 3 http://127.0.0.1:8080/actuator/health/liveness >/dev/null 2>&1; then
  echo "LimitCore preview already responds on port 8080."
  exit 0
fi
(
  export LIMITCORE_API_KEY
  LIMITCORE_API_KEY="$(cat "$keyfile")"
  export LIMITCORE_KEY_SCOPE=tenant
  export LIMITCORE_TRACING_SAMPLE_RATE=0
  exec mvn -B -ntp -DskipTests spring-boot:run
) >"$logfile" 2>&1 </dev/null &
echo "$!" > "$pidfile"

echo "LimitCore preview is starting (Java 25 + private Redis container)."
echo "Logs: tail -f $logfile"
echo "Your disposable API key is in $keyfile (do not share it)."
echo "The Codespaces port 8080 is private by default; do NOT set it public."
