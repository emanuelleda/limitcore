#!/usr/bin/env bash
set -Eeuo pipefail
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/gh" <<'MOCK'
#!/usr/bin/env bash
args="$*"
mode="${GH_MOCK_MODE:-pass}"
if [[ "$args" == *"/rules/branches/main"* ]]; then
  if [[ "$mode" == "weak-rules" ]]; then
    echo '[]'
  else
    jq -c '.rules' docs/github-ruleset-main.json
  fi
elif [[ "$args" == *"/branches/main"* ]]; then
  if [[ "$mode" == "unprotected" ]]; then echo false; else echo true; fi
elif [[ "$args" == *"/actions/runs/41/jobs"* ]]; then
  if [[ "$mode" == "review-skipped" ]]; then
    echo '{"jobs":[{"name":"dependency-review","status":"completed","conclusion":"skipped"}]}'
  else
    echo '{"jobs":[{"name":"dependency-review","status":"completed","conclusion":"success"}]}'
  fi
elif [[ "$args" == *"/actions/workflows/security.yml/runs"* && "$args" == *"event=pull_request"* ]]; then
  echo '{"workflow_runs":[{"id":41,"event":"pull_request","created_at":"2026-10-28T12:00:00Z","run_attempt":1}]}'
elif [[ "$args" == *"/actions/workflows/sonar.yml/runs"* ]]; then
  if [[ "$mode" == "sonar-failed" ]]; then result=failure; else result=success; fi
  printf '{"workflow_runs":[{"head_sha":"ci-test-sha","head_branch":"main","event":"push","status":"completed","conclusion":"%s","created_at":"2026-10-28T12:00:00Z","run_attempt":1}]}\n' "$result"
elif [[ "$args" == *"/actions/workflows/"* ]]; then
  if [[ "$mode" == "failed-check" && "$args" == *"/security.yml/"* ]]; then
    echo '{"workflow_runs":[]}'
  else
    echo '{"workflow_runs":[{"head_sha":"ci-test-sha","head_branch":"main","event":"push","status":"completed","conclusion":"success","created_at":"2026-10-28T12:00:00Z","run_attempt":1}]}'
  fi
else
  echo "Unexpected gh request: $args" >&2
  exit 2
fi
MOCK
chmod +x "$TMP/gh"
export PATH="$TMP:$PATH"
export GH_TOKEN=fixture-not-a-secret
export GITHUB_REPOSITORY=example/limitcore
export GITHUB_SHA=ci-test-sha
export GITHUB_STEP_SUMMARY="$TMP/summary.md"

GH_MOCK_MODE=pass bash scripts/verify-repository-readiness.sh >"$TMP/pass.log" 2>&1 || {
  cat "$TMP/pass.log"
  echo "Expected a successful readiness preflight" >&2
  exit 1
}

for mode in unprotected weak-rules review-skipped sonar-failed failed-check; do
  : > "$GITHUB_STEP_SUMMARY"
  if GH_MOCK_MODE="$mode" bash scripts/verify-repository-readiness.sh >"$TMP/$mode.log" 2>&1; then
    echo "Readiness preflight must fail closed for: $mode" >&2
    exit 1
  fi
done
echo "Repository preflight tests passed (positive and five negative cases)."
