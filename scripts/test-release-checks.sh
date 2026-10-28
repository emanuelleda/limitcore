#!/usr/bin/env bash
set -Eeuo pipefail

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/gh" <<'MOCK'
#!/usr/bin/env bash
if [[ "${GH_MOCK_FAIL_WORKFLOW:-}" != "" && "$*" == *"$GH_MOCK_FAIL_WORKFLOW"* ]]; then
  printf '%s\n' '{"workflow_runs":[{"head_sha":"ci-test-sha","head_branch":"main","event":"push","conclusion":"failure"}]}'
else
  printf '{"workflow_runs":[{"head_sha":"%s","head_branch":"main","event":"push","conclusion":"success"}]}\n' "${GH_MOCK_RESULT_SHA:-ci-test-sha}"
fi
MOCK
chmod +x "$TMP/gh"

export PATH="$TMP:$PATH"
export GH_TOKEN=ci-fixture-token
export GITHUB_REPOSITORY=example/limitcore
export GITHUB_SHA=ci-test-sha

bash scripts/verify-release-checks.sh >"$TMP/pass.log" || {
  cat "$TMP/pass.log"
  echo "Release gate rejected valid successful runs"
  exit 1
}

export GH_MOCK_FAIL_WORKFLOW=security.yml
if bash scripts/verify-release-checks.sh >"$TMP/failure.log" 2>&1; then
  echo "Release gate accepted a failing Security workflow"
  exit 1
fi

unset GH_MOCK_FAIL_WORKFLOW
export GH_MOCK_RESULT_SHA=another-commit
if bash scripts/verify-release-checks.sh >"$TMP/mismatch.log" 2>&1; then
  echo "Release gate accepted successful checks for the wrong SHA"
  exit 1
fi

echo "Exact-SHA release gate passed positive and negative tests"
