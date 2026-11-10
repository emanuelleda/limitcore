#!/usr/bin/env bash
# Start/inspect a temporary Codespaces preview. It never uses production config.
set -Eeuo pipefail
cd /workspaces/limitcore
state="$HOME/.local/state/limitcore-demo"
keyfile="$state/api-key"
logfile="$state/app.log"
session="limitcore-demo"
mode="${1:-start}"
if [[ "$mode" != "start" && "$mode" != "--background" && "$mode" != "--status" && "$mode" != "--restart" ]]; then
  echo "Usage: bash .devcontainer/start-demo.sh [--background|--status|--restart]" >&2
  exit 2
fi
umask 077
mkdir -p "$state"
chmod 700 "$state"

health() { curl -fsS --connect-timeout 2 --max-time 3 http://127.0.0.1:8080/actuator/health/liveness >/dev/null 2>&1; }
readiness() { curl -fsS --connect-timeout 2 --max-time 3 http://127.0.0.1:8080/actuator/health/readiness >/dev/null 2>&1; }
session_live() { tmux has-session -t "=$session" 2>/dev/null; }
diagnose() {
  echo "Recent preview logs:"
  if [[ -f "$logfile" ]]; then
    tail -n 35 "$logfile"
  else
    echo "(No log file was produced.)"
  fi
  echo "Tip: tail -f ~/.local/state/limitcore-demo/app.log"
}

if ! command -v tmux >/dev/null; then
  echo "tmux is missing from this Codespace image. Rebuild the container (Command Palette → Codespaces: Rebuild Container), then retry." >&2
  exit 1
fi

if [[ "$mode" == "--status" ]]; then
  if health; then
    echo "LimitCore liveness: UP (port 8080)"
    if readiness; then
      echo "LimitCore readiness: UP (Redis available)"
    else
      echo "WARNING: readiness is not UP. Check Redis and logs." >&2
      diagnose
      exit 1
    fi
  elif session_live; then
    echo "LimitCore process is running but not healthy on port 8080 yet."
    diagnose
    exit 1
  else
    echo "LimitCore demo is NOT running."
    diagnose
    exit 1
  fi
  exit 0
fi

if [[ "$mode" == "--restart" ]] && session_live; then
  echo "Stopping the existing demo session..."
  tmux kill-session -t "=$session"
fi
if health; then
  echo "LimitCore is already listening on port 8080."
  if readiness; then echo "Redis readiness: UP"; else echo "WARNING: Redis readiness is not UP"; fi
  exit 0
fi

if [[ ! -s "$keyfile" ]]; then
  head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$keyfile"
fi
chmod 600 "$keyfile"

if ! session_live; then
  : > "$logfile"
  # A detached tmux server survives the VS Code postStart lifecycle shell.
  # The private API key is read by run-demo.sh, never passed on the command line.
  tmux new-session -d -s "$session" 'bash .devcontainer/run-demo.sh'
  echo "Starting LimitCore with Java 25, Maven and private Redis."
else
  echo "Existing Maven session detected; checking API readiness (not just a PID)."
fi
echo "Logs: $logfile"

# The postStart hook must return promptly so Codespaces can open the editor.
if [[ "$mode" == "--background" ]]; then
  exit 0
fi

# Cold Maven downloads may take a while. Never call the API ready based only on
# the presence of a process. Preserve the session if startup times out.
for ((attempt=1; attempt<=90; attempt++)); do
  if health; then
    echo "PASS: LimitCore liveness UP on http://localhost:8080"
    if readiness; then
      echo "PASS: Redis readiness UP; API is ready."
      exit 0
    fi
    echo "WARNING: API started but Redis readiness is not UP." >&2
    diagnose
    exit 1
  fi
  if ! session_live; then
    echo "ERROR: the preview process exited before becoming healthy." >&2
    diagnose
    exit 1
  fi
  sleep 2
done

echo "The preview is still not responding after 180 seconds." >&2
echo "If Maven is still downloading dependencies, inspect logs and retry --status." >&2
diagnose
exit 1
