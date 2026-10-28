#!/usr/bin/env bash
# Require green checks for exactly the commit being published; no release by tag alone.
set -Eeuo pipefail
: "${GH_TOKEN:?GH_TOKEN is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${GITHUB_SHA:?GITHUB_SHA is required}"

for workflow in ci.yml security.yml smoke.yml sentinel.yml production-tls.yml load-validation.yml; do
  echo "Checking $workflow for commit $GITHUB_SHA..."
  runs="$(gh api --method GET \
      "repos/$GITHUB_REPOSITORY/actions/workflows/$workflow/runs" \
      -f head_sha="$GITHUB_SHA" -f per_page=100)"
  # Inspect the latest matching run, not just any historical successful attempt.
  # A newer failed/incomplete run on the exact release SHA must block publication.
  if ! jq -e --arg sha "$GITHUB_SHA" '
      [.workflow_runs[]
        | select(.head_sha == $sha and .event == "push" and .head_branch == "main")]
      | sort_by(.created_at, .run_attempt)
      | last
      | (.status == "completed" and .conclusion == "success")
    ' <<< "$runs" >/dev/null; then
    echo "::error::Latest main-branch $workflow run is missing, incomplete or failing on $GITHUB_SHA"
    exit 1
  fi
done
echo "Required CI, security, smoke, failover, TLS and load baseline checks passed"
