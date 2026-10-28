# Go / No-Go: liberação do LimitCore

**Estado em 28/10/2026:** `NO-GO` para produção real. O commit `79ccc357` passou em CI, Security, SonarQube, Smoke, Sentinel, Redis TLS e Load Baseline, **mas** os ensaios de runner não certificam a infraestrutura real.

## A. Controles administrativos do GitHub

O ruleset versionado inclui `sonar` nos checks obrigatórios, além de CI, CodeQL, Trivy, smoke, Redis TLS, Sentinel e carga. **Só passa a valer quando for aplicado ao GitHub.**

1. Com conta com permissão **Administration: write**, autentique `gh` com `gh auth login`.
2. Execute `bash scripts/apply-branch-protection.sh`. Confirme [Settings → Rules](https://github.com/emanuelleda/limitcore/settings/rules) e que `main` esteja protegida. Exigir PR revisado por outra pessoa, checks verdes, nenhuma exclusão ou force-push e nenhuma exceção não justificada.
3. Teste que um PR com check propositalmente falhando **não pode ser mesclado**.
4. Em [Settings → Security & analysis](https://github.com/emanuelleda/limitcore/settings/security_analysis), habilite Dependency graph (se disponível ao repositório).
5. Em Settings → Secrets and variables → Actions → Variables, configure `LIMITCORE_DEPENDENCY_REVIEW_ENABLED=true`; abra um PR e confirme que o job **dependency-review executou e passou**, sem ser `skipped`.
6. Execute manualmente [Production Preflight (Repository Controls)](https://github.com/emanuelleda/limitcore/actions/workflows/production-preflight.yml) na `main`. Se houver falha, **não publique**. Essa auditoria não substitui testes de produção.

Se o plano/permissões do GitHub não oferecer suporte ao requisito de aprovação ou Dependency Review, **registre o bloqueio e use um fluxo com as proteções equivalentes antes de dar GO**. Não desative verificações só para obter verde.

## B. Infraestrutura do ambiente de staging / produção

O repositório **não provisiona automaticamente** cluster, Redis, DNS, TLS público, cofre, backups nem alertas. Escolha e registre provedor, região, topologia Redis HA/TLS, orçamento e responsáveis.

- API em `SPRING_PROFILES_ACTIVE=production`, várias instâncias por zona, ingress HTTPS e autenticação/rate limiting na borda.
- Redis TLS/autenticado, ACL de menor privilégio, autenticação e isolamento de rede, backups **com restauração ensaiada**, alarmes e retenção.
- Segredos aleatórios individuais por tenant de no mínimo 32 bytes; cofre, rotação e revogação testadas; nunca commitá-los.
- Escopo correto de quota: por tenant por padrão; por identidade apenas se derivada de autenticação confiável. Lua garante atomicidade por primário, **não** durabilidade de incrementos em failover.
- Logs, métricas e traces protegidos; Alertmanager ligado a um destinatário real com alerta de teste; SLO acordado.

O arquivo `deploy/k8s/limitcore.example.yaml` é uma referência com placeholders. **Não** executar `kubectl apply` nele sem substituir endereços, imagem por digest e segredos fora do Git.

## C. Evidências mínimas de staging

1. Faça rollout da imagem candidata por **digest imutável**, com pelo menos duas instâncias API e Redis na topologia representativa.
2. Carregue `LIMITCORE_STAGING_URL` (HTTPS), `LIMITCORE_API_KEY` via cofre e `LIMITCORE_STAGING_ACK=staging-only`. Execute `bash scripts/staging-smoke.sh` para liveness, readiness, decisão válida e resposta 401 para chave inválida. **Não execute no serviço de clientes.**
3. Execute `k6 run benchmarks/k6.js` com `LIMITCORE_URL`, `LIMITCORE_API_KEY`, VUs, duração, cardinalidade e orçamento p95 definidos previamente. Repetir por algoritmo e com escala de tenants representativa.
4. Durante tráfego de teste, provoque failover do primário Redis **somente no staging**, documentando número de erros/503, reconexão, p95/p99 e eventuais incrementos perdidos. Não afirmar failover sem medição.
5. Interrompa uma instância da API, confirme readiness e continuidade das demais. Simule rollback da imagem pelo digest anterior; avalie migração de chaves Redis antes de trocar versão.
6. Restaure backup Redis em ambiente isolado e confirme integridade e retenção. Teste alerta e destinatários.
7. Guarde logs e métricas sem segredos; anote SHA, versão da imagem, digest, Redis, topologia, carga, datas, avaliador e a decisão.

## D. Aprovação e release

| Gate | Evidência exigida | Estado |
| --- | --- | --- |
| CI / segurança / Sonar no SHA de release | Links de Actions e Quality Gate | Comprovado para `79ccc357`; verificar novamente no SHA final |
| Branch protection e Dependency Review | Ruleset ativo, PR negativo impedido, review executado | Pendente — acesso administrativo |
| Staging TLS e segredos | URL e relatório de configuração sanitizado | Pendente — ambiente |
| Carga, failover, backup, rollback | Relatórios reproduzíveis no ambiente | Pendente — ambiente |
| Alertas, runbook e aprovação | Teste de notificação, responsável pelo incidente, decisão GO | Pendente — operação |

**Somente após todos os gates:**

1. Crie uma tag `vMAJOR.MINOR.PATCH` apontando para o SHA aprovado da `main` (com controle de versão imutável).
2. Aguarde `Release` e `Publish OCI Image` verdes; verifique GitHub Release, GHCR, SBOM, provenance e digest.
3. Promova digest em staging; faça smoke e reteste de rollback, depois rollout gradual na infraestrutura real com monitoramento.
4. Registre a decisão final GO com responsável e evidências, ou NO-GO e bloqueios remanescentes.

**Não criar tag apenas porque o CI está verde.** Tag é um gatilho real de publicação, não apenas uma anotação.
