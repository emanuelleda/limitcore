# Ativação dos controles externos — checklist de liberação

> Este documento separa o que já é comprovado em CI daquilo que precisa ser **ativado por um administrador** ou executado **na infraestrutura real**. Não transforme um item pendente em concluído sem evidência.

## 1. Conectar SonarQube Cloud / SonarQube Server

1. Crie ou importe `emanuelleda/limitcore` em uma organização do SonarQube Cloud, ou obtenha a URL de um servidor SonarQube já provisionado.
2. Gere o token **no próprio SonarQube**; não o inclua em commits, logs ou mensagens.
3. Acesse **GitHub → limitcore → Settings → Secrets and variables → Actions** e configure:
   - Secret: `SONAR_TOKEN`.
   - Variable: `SONAR_PROJECT_KEY` (chave exata do projeto Sonar).
   - Variable: `SONAR_ORGANIZATION` (se utilizar SonarQube Cloud).
   - Variable: `SONAR_HOST_URL` (se utilizar servidor próprio).
4. Execute [SonarQube Actions](https://github.com/emanuelleda/limitcore/actions/workflows/sonar.yml) e confira o **Quality Gate aprovado** no projeto real.
5. A publicação por tag exige novamente Quality Gate e **falha fechada** se faltarem as configurações.

**Confirmado em 28/10/2026:** o workflow SonarQube na `main` concluiu com sucesso no SHA `79ccc357` ([evidência](https://github.com/emanuelleda/limitcore/actions/runs/40748495394)). A proteção da branch exigindo Sonar ainda depende da ativação do ruleset (issue #13).

## 2. Dependency Graph e Dependency Review

**Validação em 03/11/2026:** o job nativo `dependency-review` executou com **success** no [PR #26](https://github.com/emanuelleda/limitcore/pull/26), comprovando que o recurso está operacional para este repositório.

1. Mantenha o **Dependency Graph** habilitado em [Advanced Security](https://github.com/emanuelleda/limitcore/settings/security_analysis). Se o GitHub sinalizar indisponibilidade, corrija a configuração antes do merge.
2. O PR #26 remove o opt-in antigo: o job `dependency-review` passa a executar em **todos os PRs**, sem depender de `LIMITCORE_DEPENDENCY_REVIEW_ENABLED`.
3. O PR #26 foi mesclado, e o ruleset ativo exige `dependency-review`. O script `bash scripts/require-dependency-review-check.sh` pode ser usado para verificar a configuração com GitHub CLI autenticado (Administration: write); se o check já existir, não o duplica.
4. Teste um PR com problema de dependência e confirme que o check reprovado impede o merge. Mantenha o `dependency-audit` (Trivy) como proteção complementar.

Não confunda o sucesso do job em PR com ativação efetiva da exigência no ruleset.

## 3. Proteger a main sem depender de configurações manuais repetitivas

O repositório inclui o modelo [github-ruleset-main.json](github-ruleset-main.json) e o script [apply-branch-protection.sh](../scripts/apply-branch-protection.sh). O modelo exige PR sem revisão humana (decisão do mantenedor), mas mantém CI, SonarQube, Trivy, CodeQL, Dependency Review, recuperação Redis, Sentinel, TLS e benchmark de carga.

De um terminal local **autenticado como administrador do repositório**:

```bash
gh auth login
gh auth status
bash scripts/apply-branch-protection.sh
```

**Pré-requisito:** seu token do GitHub CLI precisa de permissão **Administration: write** para o repositório (quando aplicável). O script consulta os workflows, recusa criar uma regra duplicada e verifica as regras efetivas.

No PR #27, o GitHub bloqueou a tentativa de merge enquanto os checks eram esperados (HTTP 405) e permitiu o squash merge após 15 checks aprovados. A aprovação externa foi desativada a pedido do mantenedor; PR, 15 checks e bloqueio a force-push permanecem obrigatórios.

GitHub REST: [regras de repositório](https://docs.github.com/en/rest/repos/rules).

## 4. Infraestrutura real e homologação

Configure o ambiente do usuário e registre provas, não suposições:

- **Infraestrutura e rede:** provedor/região, DNS, HTTPS no ingress, limite por origem/IP, isolamento do Redis e NetworkPolicy específica para o cluster; `deploy/k8s/*.example.yaml` contém placeholders e não é diretamente implantável.
- **Segredos:** cofre externo, Redis TLS com autenticação, `LIMITCORE_TENANTS` com chaves aleatórias únicas por tenant, rotação/revogação e controle de acesso operacional.
- **Alta disponibilidade:** réplicas Redis/Sentinel/Cluster em hosts/zones separados, backups e restauração testada, dimensionamento de memória e latência entre aplicação e Redis.
- **Observabilidade:** Prometheus protegido, Jaeger/OTLP com políticas de acesso, Alertmanager com destino e teste de disparo, SLO definidos (p95/p99, erros 5xx, disponibilidade).
- **Benchmark representativo:** execute `benchmarks/k6.js` em staging com topologia, quotas, número de tenants e cardinalidade próximos à produção. Registre o SHA, CPU/memória, requisições/s, p95/p99, aceitação/recusa, Redis e limites de SLO.
- **Resiliência:** teste desligamento do primário sob carga, perda/latência de rede, réplica promovida, comportamento 503, perda potencial de incrementos e recuperação/rollback do release.
- **Governança:** revisão independente de segurança e aprovação registrada por responsável pela operação, inclusive procedimentos de incidente, rollback e indisponibilidade.

O workflow **Load Baseline Evidence** gera uma referência reprodutível em runner efêmero. **Não é teste representativo de produção.** Não reutilize os números do CI como SLA.

## 5. Liberação versionada

Apenas após validar 1–4:

1. Verifique os artefatos dos workflows obrigatórios **no mesmo SHA da main** e confirme o SonarQube.
2. Crie uma tag imutável SemVer `vMAJOR.MINOR.PATCH` desse commit aprovado.
3. Confirme GitHub Release, imagem GHCR, SBOM, proveniência, Trivy e digest da imagem real.
4. Promova primeiro em staging, faça smoke + benchmark + failover, depois rollout gradual com rollback pronto.
5. Registre a decisão **GO / NO-GO**, responsáveis, evidências e versão realmente operante.

**Estado (03/11/2026):** o ruleset da `main` está ativo; SonarQube e CI verdes; o Dependency Review passou no PR #26, aguardando revisão/merge e inclusão no ruleset. Ainda falta comprovar staging. Consulte [Go / No-Go](release-go-no-go.md) e o [Production Preflight](https://github.com/emanuelleda/limitcore/actions/workflows/production-preflight.yml). Prontidão operacional depende de evidências externas. Issues [#7](https://github.com/emanuelleda/limitcore/issues/7), [#8](https://github.com/emanuelleda/limitcore/issues/8), [#10](https://github.com/emanuelleda/limitcore/issues/10) e [#13](https://github.com/emanuelleda/limitcore/issues/13) acompanham os bloqueios restantes.
