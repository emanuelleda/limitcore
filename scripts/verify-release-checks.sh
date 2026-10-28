#!/usr/bin/env bash
# Require green checks for exactly the commit being published; no release by tag alone.
set -Eeuo pipefail
: "${GH_TOKEN:?GH_TOKEN is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${GITHUB_SHA:?GITHUB_SHA is required}"

for workflow in ci.yml security.yml smoke.yml sentinel.yml production-tls.yml; do
  echo "Checking $workflow for commit $GITHUB_SHA..."
  runs="$(gh api --method GET \
      "repos/$GITHUB_REPOSITORY/actions/workflows/$workflow/runs" \
      -f head_sha="$GITHUB_SHA" -f per_page=100)"
  passed="$(jq --arg sha "$GITHUB_SHA" \
      '[.workflow_runs[] | select(.head_sha == $sha and .event == "push" and .head_branch == "main" and .conclusion == "success")] | length' \
      <<< "$runs")"
  if [[ "$passed" -lt 1 ]]; then
    echo "::error::Missing successful main-branch $workflow run on $GITHUB_SHA"
    exit 1
  fi
done
echo "Required CI, security, smoke, failover and production TLS checks passed"
