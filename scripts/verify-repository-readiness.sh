#!/usr/bin/env bash
# Repository-only preflight. Success never certifies external production infrastructure.
set -Eeuo pipefail
: "${GH_TOKEN:?GH_TOKEN required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY required}"
: "${GITHUB_SHA:?GITHUB_SHA required}"
command -v gh >/dev/null
command -v jq >/dev/null

failed=0
report() {
  local label="$1" passed="$2"
  if [[ "$passed" == "true" ]]; then
    echo "PASS: $label"
    echo "| $label | PASS |" >> "$GITHUB_STEP_SUMMARY"
  else
    echo "::error::$label"
    echo "| $label | FAIL |" >> "$GITHUB_STEP_SUMMARY"
    failed=$((failed + 1))
  fi
}

echo "## Repository preflight — $GITHUB_SHA" >> "$GITHUB_STEP_SUMMARY"
echo "| Gate | Resultado |" >> "$GITHUB_STEP_SUMMARY"
echo "| --- | --- |" >> "$GITHUB_STEP_SUMMARY"

protected="$(gh api "repos/$GITHUB_REPOSITORY/branches/main" --jq '.protected')"
report "Branch main protegida" "$protected"

# Verify effective rules, not merely a `protected=true` flag. The read-only
# branch rules API exposes active repository/organization rulesets.
effective_rules="$(gh api "repos/$GITHUB_REPOSITORY/rules/branches/main")"
if jq -e '[.[] | select(.type == "pull_request" and (.parameters.required_approving_review_count // 0) >= 1)] | length > 0' <<< "$effective_rules" >/dev/null; then
  report "PR obrigatório com pelo menos uma aprovação" true
else
  report "Falta PR obrigatório com aprovação na main" false
fi
while IFS= read -r context; do
  if jq -e --arg context "$context" '[.[] | select(.type == "required_status_checks") | .parameters.required_status_checks[]? | .context] | index($context) != null' <<< "$effective_rules" >/dev/null; then
    report "Check exigido no ruleset: $context" true
  else
    report "Check AUSENTE no ruleset efetivo: $context" false
  fi
done < <(jq -r '.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context' docs/github-ruleset-main.json)

if bash scripts/verify-release-checks.sh; then
  report "CI, Security, smoke, Sentinel, Redis TLS e load no SHA da main" true
else
  report "Checks obrigatórios não concluídos com sucesso no SHA da main" false
fi

sonar_runs="$(gh api --method GET "repos/$GITHUB_REPOSITORY/actions/workflows/sonar.yml/runs" -f head_sha="$GITHUB_SHA" -f per_page=100)"
if jq -e --arg sha "$GITHUB_SHA" '
  [.workflow_runs[]
    | select(.head_sha == $sha and .event == "push" and .head_branch == "main")]
    | sort_by(.created_at, .run_attempt) | last
    | (.status == "completed" and .conclusion == "success")
  ' <<< "$sonar_runs" >/dev/null; then
  report "SonarQube na main" true
else
  report "SonarQube sem execução bem-sucedida no SHA da main" false
fi

# A skipped dependency-review job is NOT considered a passed native review.
security_runs="$(gh api --method GET "repos/$GITHUB_REPOSITORY/actions/workflows/security.yml/runs" -f event=pull_request -f per_page=30)"
latest_pr_run="$(jq -r '[.workflow_runs[] | select(.event == "pull_request")] | sort_by(.created_at, .run_attempt) | last | .id // empty' <<< "$security_runs")"
if [[ -n "$latest_pr_run" ]]; then
  jobs="$(gh api --method GET "repos/$GITHUB_REPOSITORY/actions/runs/$latest_pr_run/jobs" -f per_page=100)"
  if jq -e '[.jobs[] | select(.name == "dependency-review" and .status == "completed" and .conclusion == "success")] | length > 0' <<< "$jobs" >/dev/null; then
    report "Dependency Review nativo executado (último Security PR)" true
  else
    report "Dependency Review nativo ausente, pulado ou reprovado no último Security PR" false
  fi
else
  report "Nenhum Security PR run encontrado para comprovar Dependency Review" false
fi

echo "" >> "$GITHUB_STEP_SUMMARY"
echo "> Esta auditoria cobre apenas GitHub/CI. Infraestrutura, segredos, HA, carga real, backup, rollback e alertas exigem validação separada. Nunca interpretar PASS como autorização para deploy." >> "$GITHUB_STEP_SUMMARY"
if (( failed > 0 )); then
  echo "::error::$failed gate(s) de repositório falharam. NÃO realizar release produtiva."
  exit 1
fi
echo "Controles do repositório passaram; validação de infraestrutura e go/no-go permanecem obrigatórios."
