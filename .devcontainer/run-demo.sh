#!/usr/bin/env bash
# Foreground process owned by the detached tmux session.
set -Eeuo pipefail
cd /workspaces/limitcore
state="$HOME/.local/state/limitcore-demo"
keyfile="$state/api-key"
logfile="$state/app.log"
[[ -s "$keyfile" && -r "$keyfile" ]] || {
  echo "The demo API key is missing; rerun start-demo.sh." >&2
  exit 1
}
export LIMITCORE_API_KEY="$(cat "$keyfile")"
export LIMITCORE_KEY_SCOPE=tenant
export LIMITCORE_TRACING_SAMPLE_RATE=0
# Do not log the key or pass its value in process arguments.
exec mvn -B -ntp -DskipTests spring-boot:run >>"$logfile" 2>&1
