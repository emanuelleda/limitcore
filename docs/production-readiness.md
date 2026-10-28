# Critérios de prontidão para produção — LimitCore

**Situação:** candidato técnico em validação; **não certificado para implantação produtiva**. CI verde, por si só, não substitui configuração externa, testes de capacidade, recuperação de desastre nem revisão de segurança independente.

## Implementado ou preparado no repositório

- API Java 25 e Spring Boot 4.1.2, Redis Lua atômico, quotas por tenant, cardinalidade limitada e rotação gradual por configuração.
- Autenticação por credenciais SHA-256 pré-computadas, limite de corpo JSON de 1 KiB e limite de cabeçalhos no perfil de produção.
- O perfil de produção usa `LIMITCORE_KEY_SCOPE=tenant` para impedir que um consumidor escape da quota alterando o campo `key`; o modo `identifier` só é seguro com identificadores fornecidos por um serviço confiável.
- Resposta HTTP 503 sem decisão positiva diante de indisponibilidade Redis; `allowed=false` continua retornando HTTP 200.
- `SPRING_PROFILES_ACTIVE=production` obriga credenciais API de pelo menos 32 bytes, TLS Redis e senha Redis de pelo menos 16 bytes, limita threads/conexões, habilita desligamento gracioso e desativa amostragem de traces por padrão.
- Probes `/actuator/health/liveness` (não depende de Redis) e `/actuator/health/readiness` (depende de Redis).
- Testes unitários, integração Testcontainers, concorrência e quota, k6 smoke, perfil `production` com Redis TLS/senha e recuperação, parada/reinício Redis e simulação de failover Sentinel com três sentinels e dois nós Redis no CI.
- Cobertura JaCoCo com limites mínimos de 90% de linhas e 75% de ramificações, CodeQL, Docker não-root, CI para build de imagem, varredura Trivy de vulnerabilidades corrigíveis HIGH/CRITICAL, SBOM CycloneDX.
- Workflow para publicar imagem GHCR por tag versionada, com scan anterior ao push, SBOM, provenance, Quality Gate SonarQube e exigência de cinco workflows aprovados no SHA da release. **Publicação real por tag ainda não foi executada.**
- Referência de K8s com réplicas, liveness/readiness, PDB, HPA, UID fixo, sistema de arquivos somente leitura e imagem por digest. **Não foi implantada.**
- Prometheus e regras de alerta para indisponibilidade, erro, p95 e autenticação. **Alertmanager e canais de notificação precisam ser conectados.**

## Critérios de liberação (não preencher por suposição)

| Critério | Verificação necessária |
| --- | --- |
| CI, CodeQL, Trivy, smoke, Sentinel, Redis TLS autenticado, benchmark de CI e imagem | Todos verdes no SHA candidato, com artefatos retidos |
| Trivy e dependências | Nenhum alerta HIGH/CRITICAL corrigível; demais riscos documentados |
| SonarQube | Token e organização conectados; Quality Gate efetivamente aprovado; releases agora bloqueadas quando a integração não estiver configurada |
| Dependency Review | Dependency Graph habilitado; checagem operante em pull request |
| Proteção da branch principal | Regras de proteção na `main` com PR, CI, CodeQL, smoke, failover e bloqueio de bypass configuradas no GitHub |
| Versão | Tag SemVer de commit na `main`, GHCR publicado e digest pinado; SBOM e provenance verificáveis |
| Infraestrutura | Redis TLS/autenticado, HA, backups, certificação de certificados, recursos e isolamento de rede |
| Segredos e acesso | Cofre de segredos, rotação e revogação testadas, TLS da API/ingress, controle de origens |
| Escopo das quotas | Verificar se a quota deve ser por tenant ou por identidade; impedir identificadores de quota manipuláveis por usuários finais |
| Alta disponibilidade real | Teste de falha de primário, partições, latência e recuperação na topologia adotada |
| Capacidade e SLO | k6 representativo, taxas de aceitação/recusa, memória, CPU, p95/p99, metas e relatórios |
| Observabilidade | Métricas protegidas, dashboard, alertas com destinatário e teste de disparo |
| Segurança e rollback | Revisão independente, threat model, resposta a incidentes, rollback e recuperação testados |

## Procedimento de preparação para rollout

1. Configure proteção da branch `main` usando [o modelo versionado](github-ruleset-main.json) com uma credencial administrativa, segredos SonarQube e aprovação do Quality Gate. Revise os artefatos do workflow e as dependências. Nunca ignore alertas apenas para deixar o pipeline verde.
2. Construa uma imagem por tag a partir da `main`; use o digest publicado no deployment.
3. Configure infraestrutura Redis/Sentinel e credenciais em um cofre. Configure `REDIS_SSL_ENABLED=true`.
4. Inicie o perfil `production` em *staging*; exija 401 para credenciais inválidas, 413 para payloads grandes e readiness 503 quando Redis está indisponível.
5. Execute benchmarks e ensaios de failover no ambiente de destino. Registre SHA, configuração, carga e resultados.
6. Teste rede, HTTPS, DNS, backups, certificados, revogação de credenciais, telemetria e alertas.
7. Faça rollout gradual e monitore taxa de erros 5xx, latência, pressão do Redis e decisões `allowed=false`.
8. Documente o procedimento de reversão e defina responsáveis pela operação antes de liberar tráfego real.

## Perigos residuais e contratos

- Redis Sentinel é **eventualmente consistente**: replicação assíncrona pode perder incrementos em failover. Para limites financeiros, segurança crítica ou cobrança, considere serviço com garantias de durabilidade mais fortes.
- A mesma hash tag por tenant concentra a escrita de todo um tenant em um slot do Redis Cluster; dimensionar o app não elimina essa pressão.
- Os limites de cardinalidade são por tenant e não representam limite físico garantido de memória Redis.
- Rotação de credenciais não é dinâmica: um rollout de configuração é necessário para a revogação.
- No perfil de produção todos os `key` enviados por um tenant compartilham o mesmo limite por padrão; usar `identifier` exige uma integração que derive a identidade de um contexto autenticado.
- `X-API-Key` identifica o tenant; clientes de API usam HTTP 200 e campo `allowed` para a decisão. O gateway consumidor precisa implementar o bloqueio; não é proxy nem substitui WAF/rate limiting na borda.
- A alteração de formato das chaves Redis realizada em uma versão anterior reiniciou quotas ativas. Planeje as futuras migrações de formatos com transição controlada.
- A segurança do cluster, certificados e disponibilidade contínua não pode ser atestada apenas por arquivos versionados.

Consulte [execução de carga](load-testing.md), [operações e incidentes](operations.md), [referência de implantação](../deploy/k8s/README.md) e [política de segurança](../SECURITY.md).

Veja o procedimento detalhado em [Ativação dos controles externos](external-activation.md).

## Estado dos controles externos

- **GitHub Rulesets/branch protection:** a `main` não estava protegida na auditoria deste ciclo. É necessário configurá-la em **Settings → Rules → Rulesets** (ou Branch protection) e exigir revisões e checks de PR. O acesso da integração usada nesta auditoria não permite alterar regras administrativas.
- **SonarQube:** o workflow contínuo permanece `skipped` enquanto faltarem credenciais/variáveis; release e publicação de imagens passam a falhar explicitamente sem Quality Gate. Além disso, os workflows de release verificam no GitHub que CI, segurança, smoke, Sentinel e TLS de produção foram aprovados para o mesmo commit.
- **Infraestrutura real:** não há evidência de cluster Redis TLS com HA, cofre de segredos, ingress TLS, restauração de backup, destinatários de alertas e testes de carga representativos conectados a este repositório. Não deduza aprovação desses controles a partir de um workflow verde.
