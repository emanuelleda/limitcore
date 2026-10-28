#!/usr/bin/env bash
set -Eeuo pipefail

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/gh" <<'MOCK'
#!/usr/bin/env bash
# Mock only the GitHub workflow-runs response. No remote network access.
case "${GH_MOCK_MODE:-pass}" in
  pass)
    cat <<'JSON'
{"workflow_runs":[{"head_sha":"ci-test-sha","head_branch":"main","event":"push","status":"completed","conclusion":"success","created_at":"2026-10-28T10:00:00Z","run_attempt":1}]}
JSON
    ;;
  latest-failed)
    cat <<'JSON'
{"workflow_runs":[{"head_sha":"ci-test-sha","head_branch":"main","event":"push","status":"completed","conclusion":"failure","created_at":"2026-10-28T11:00:00Z","run_attempt":1},{"head_sha":"ci-test-sha","head_branch":"main","event":"push","status":"completed","conclusion":"success","created_at":"2026-10-28T10:00:00Z","run_attempt":1}]}
JSON
    ;;
  pending)
    cat <<'JSON'
{"workflow_runs":[{"head_sha":"ci-test-sha","head_branch":"main","event":"push","status":"in_progress","conclusion":null,"created_at":"2026-10-28T10:00:00Z","run_attempt":1}]}
JSON
    ;;
  wrong-sha)
    cat <<'JSON'
{"workflow_runs":[{"head_sha":"different-commit","head_branch":"main","event":"push","status":"completed","conclusion":"success","created_at":"2026-10-28T10:00:00Z","run_attempt":1}]}
JSON
    ;;
  wrong-branch)
    cat <<'JSON'
{"workflow_runs":[{"head_sha":"ci-test-sha","head_branch":"feature","event":"pull_request","status":"completed","conclusion":"success","created_at":"2026-10-28T10:00:00Z","run_attempt":1}]}
JSON
    ;;
  missing-security)
    if [[ "$*" == *"security.yml"* ]]; then
      printf '%s\n' '{"workflow_runs":[]}'
    else
      GH_MOCK_MODE=pass "$0" "$@"
    fi
    ;;
  *)
    exit 2
    ;;
esac
MOCK
chmod +x "$TMP/gh"

export PATH="$TMP:$PATH"
export GH_TOKEN=ci-fixture-token
export GITHUB_REPOSITORY=example/limitcore
export GITHUB_SHA=ci-test-sha

GH_MOCK_MODE=pass bash scripts/verify-release-checks.sh >"$TMP/pass.log" || {
  cat "$TMP/pass.log"
  echo "Release gate rejected successful latest checks"
  exit 1
}

for scenario in latest-failed pending wrong-sha wrong-branch missing-security; do
  if GH_MOCK_MODE="$scenario" bash scripts/verify-release-checks.sh >"$TMP/$scenario.log" 2>&1; then
    echo "Release gate incorrectly accepted scenario: $scenario"
    exit 1
  fi
done

echo "Exact-SHA release gate passed all positive and negative checks"
