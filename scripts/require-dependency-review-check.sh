#!/usr/bin/env bash
# Add the validated native Dependency Review check to the existing active ruleset.
# Only run after PR #26 is merged. Requires gh auth with repository Administration:write.
set -Eeuo pipefail

REPO="emanuelleda/limitcore"
RULESET_NAME="LimitCore main - reviewed production gates"
CHECK="dependency-review"

command -v gh >/dev/null || { echo "Missing gh CLI" >&2; exit 1; }
command -v jq >/dev/null || { echo "Missing jq" >&2; exit 1; }
gh auth status --hostname github.com >/dev/null

# Never configure a mandatory check before its workflow is merged into main.
pr_merged="$(gh api "repos/$REPO/pulls/26" --jq '.merged')"
if [[ "$pr_merged" != "true" ]]; then
  echo "PR #26 is not merged. Obtain an independent approval and merge first." >&2
  exit 1
fi

rulesets="$(gh api "repos/$REPO/rulesets")"
id="$(jq -r --arg name "$RULESET_NAME" '[.[] | select(.name == $name and .target == "branch" and .enforcement == "active") | .id] | if length == 1 then .[0] else empty end' <<<"$rulesets")"
if [[ -z "$id" ]]; then
  echo "Exactly one matching active branch ruleset is required; refusing to modify arbitrary rules." >&2
  exit 1
fi
existing="$(gh api "repos/$REPO/rulesets/$id")"
if jq -e --arg ctx "$CHECK" '[.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[]? | .context] | index($ctx) != null' <<<"$existing" >/dev/null; then
  echo "$CHECK is already required by active ruleset $id."
  exit 0
fi

# Build the writable request from the ACTIVE ruleset, preserving existing controls.
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
jq --arg ctx "$CHECK" '
  .rules |= map(if .type == "required_status_checks" then
    .parameters.required_status_checks += [{"context":$ctx}]
  else . end)
  | {name,target,enforcement,bypass_actors,conditions,rules}
' <<<"$existing" >"$tmp"

# Abort on unexpected concurrent changes; prevent overriding another admin update.
before="$(jq -r '.updated_at' <<<"$existing")"
now="$(gh api "repos/$REPO/rulesets/$id" --jq '.updated_at')"
if [[ "$before" != "$now" ]]; then
  echo "Ruleset changed during preparation. Inspect it before retrying." >&2
  exit 1
fi

echo "Adding required check $CHECK to existing active ruleset $id..."
gh api -X PUT "repos/$REPO/rulesets/$id" -H "Accept: application/vnd.github+json" --input "$tmp" \
  --jq '{id,name,enforcement}' || {
  echo "Ruleset update failed; inspect the remote ruleset before retrying." >&2
  exit 1
}
gh api "repos/$REPO/rulesets/$id" \
  --jq '.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context' \
  | grep -Fxq "$CHECK"
echo "Verified: $CHECK is mandatory. Test a failing PR and record the blocked merge."
