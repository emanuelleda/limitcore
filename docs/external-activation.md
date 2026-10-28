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

**Não confirmado:** sem credenciais e organização de SonarQube conectadas, o workflow opcional continua `skipped`. Sua execução não é uma aprovação real.

## 2. Dependency Graph e Dependency Review

1. Acesse [Security & analysis](https://github.com/emanuelleda/limitcore/settings/security_analysis) e habilite **Dependency graph** para o repositório.
2. Confirme que a ação nativa `actions/dependency-review-action` é suportada para esse repositório.
3. Em **Settings → Secrets and variables → Actions → Variables**, configure `LIMITCORE_DEPENDENCY_REVIEW_ENABLED=true`.
4. Abra um PR de teste e confirme que o job `dependency-review` **executou** em vez de aparecer como `skipped`.
5. Como compensação, o job **`dependency-audit` com Trivy** é obrigatório independentemente do Dependency Graph e bloqueia bibliotecas com vulnerabilidades altas/críticas corrigíveis.

Não marque o item nativo como resolvido apenas pelo scanner substituto.

## 3. Proteger a main sem depender de configurações manuais repetitivas

O repositório inclui o modelo [github-ruleset-main.json](github-ruleset-main.json) e o script [apply-branch-protection.sh](../scripts/apply-branch-protection.sh). O modelo exige PR, revisão de outro colaborador, CI, Trivy, CodeQL, recuperação Redis, Sentinel, TLS e benchmark de carga.

De um terminal local **autenticado como administrador do repositório**:

```bash
gh auth login
gh auth status
bash scripts/apply-branch-protection.sh
```

**Pré-requisito:** seu token do GitHub CLI precisa de permissão **Administration: write** para o repositório (quando aplicável). O script consulta os workflows, recusa criar uma regra duplicada e verifica as regras efetivas.

Depois, abra um PR com check falhando e confirme que **o merge é bloqueado**; abra outro com aprovação válida e todos os checks verdes para confirmar que o fluxo funciona. A exigência de **uma aprovação externa** requer um colaborador revisor habilitado, o que não pode ser simulado pelo autor.

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

**Estado:** código e CI podem estar verdes; prontidão operacional depende desses passos externos. Issues [#6](https://github.com/emanuelleda/limitcore/issues/6), [#7](https://github.com/emanuelleda/limitcore/issues/7), [#8](https://github.com/emanuelleda/limitcore/issues/8), [#10](https://github.com/emanuelleda/limitcore/issues/10) e [#13](https://github.com/emanuelleda/limitcore/issues/13) acompanham os bloqueios restantes.
