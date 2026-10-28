#!/usr/bin/env bash
# Apply only with an authenticated GitHub ADMIN identity (no tokens in this repo).
# Requires: gh CLI, jq, authenticated account with repository Administration:write.
set -Eeuo pipefail
REPO="emanuelleda/limitcore"
RULE_NAME="LimitCore main - reviewed production gates"

command -v gh >/dev/null || { echo "Install GitHub CLI (gh)"; exit 1; }
command -v jq >/dev/null || { echo "Install jq"; exit 1; }
gh auth status --hostname github.com >/dev/null

if gh api "repos/$REPO/rulesets" --jq '.[] | .name' | grep -Fxq "$RULE_NAME"; then
  echo "Ruleset already exists. Review Settings > Rules > Rulesets before changing it."
  exit 0
fi

# Report missing workflow definitions before enforcing required checks.
for workflow in ci.yml security.yml sonar.yml smoke.yml sentinel.yml production-tls.yml load-validation.yml; do
  gh api "repos/$REPO/actions/workflows/$workflow" --jq .id >/dev/null || {
    echo "Missing required workflow: $workflow"
    exit 1
  }
done

echo "Creating active ruleset for main using the administrator's GitHub identity..."
gh api -X POST "repos/$REPO/rulesets" \
  -H "Accept: application/vnd.github+json" \
  --input docs/github-ruleset-main.json \
  --jq '{id: .id, name: .name, enforcement: .enforcement, url: ._links.html.href}'

echo "Verifying actual effective branch rules..."
rules="$(gh api "repos/$REPO/rules/branches/main")"
jq -e '[.[] | select(.type == "required_status_checks")] | length >= 1' <<<"$rules" >/dev/null
jq -e '[.[] | select(.type == "pull_request")] | length >= 1' <<<"$rules" >/dev/null
echo "Main now has active PR and status-check enforcement."
echo "Test by opening a PR with a deliberately failing check; merge must be blocked."
