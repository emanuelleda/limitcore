# Qualidade, testes e critérios de publicação

## Testes automatizados

O GitHub Actions executa `mvn verify`, incluindo testes unitários com JUnit/Mockito e testes de integração com Redis por meio do Testcontainers. O projeto cobre concorrência nos três algoritmos e registro limitado de identificadores; há testes de isolamento de tenants e expiração de registros no Redis.

O JaCoCo exige pelo menos **50% de cobertura de linhas**, e gera relatórios disponibilizados como artefatos do pipeline. O CI também gera e publica um SBOM CycloneDX compatível com Java 25.

## Segurança e dependências

O workflow CodeQL realiza análise estática; a imagem Docker é verificada por Trivy contra vulnerabilidades altas/críticas corrigíveis e o CI valida a execução com UID não privilegiado. A revisão automática de dependências em *pull requests* depende da ativação do Dependency graph e da variável `LIMITCORE_DEPENDENCY_REVIEW_ENABLED=true`; sem elas, esse job é ignorado. O Dependabot propõe atualizações periódicas.

## SonarQube

O workflow opcional `.github/workflows/sonar.yml` executa testes, cobertura e análise quando existem `SONAR_TOKEN` (secret) e `SONAR_PROJECT_KEY` (variable). Configure também `SONAR_ORGANIZATION` para SonarCloud e, quando aplicável, `SONAR_HOST_URL`. Se `SONAR_PROJECT_KEY` não estiver definido, o job Sonar será **ignorado**, sem apresentar uma análise fictícia como aprovação; caso a chave exista sem token, a execução falha. O arquivo `sonar-project.properties` define os caminhos de análise. Não publique tokens. **Uma aprovação de quality gate do SonarQube ainda não foi demonstrada.**

## Smoke, benchmark e dependências

O workflow `Redis Sentinel Failover` exercita quórum de três sentinels, eleição de réplica e reconexão. O workflow `API Smoke and Redis Recovery` executa `benchmarks/smoke.js` com k6, valida o comportamento em uma parada de Redis e verifica retorno após reinício. Os limiares deste teste são de **sanidade do endpoint**, não metas de escala para produção. O `benchmarks/k6.js` aceita quantidade de VUs, duração, número de identificadores e limiar p95 parametrizados para execuções controladas. Consulte [guia de benchmark](load-testing.md). Ainda não há resultados de carga representativa publicados.

A ação `dependency-review` depende de o **Dependency graph** estar habilitado nas configurações de segurança do GitHub. Enquanto isso não estiver configurado, o job correspondente só é ativado quando a variável do repositório `LIMITCORE_DEPENDENCY_REVIEW_ENABLED=true` for definida. CodeQL, CI e Dependabot têm configuração separada.

## Publicação de versões

Os workflows `Release` e `Publish OCI Image` são acionados por tags SemVer no formato `vMAJOR.MINOR.PATCH` que pertençam à `main`. Ambos exigem testes e uma **análise SonarQube conectada com Quality Gate aprovado** (`SONAR_PROJECT_KEY` e `SONAR_TOKEN`). Enquanto essa integração não estiver configurada, uma publicação versionada deve falhar, em vez de prosseguir sem a qualidade exigida.

O workflow `Release` produz JAR com versão sem `SNAPSHOT` igual à tag e inclui um SBOM CycloneDX. `Publish OCI Image` compila a mesma versão para uma imagem GHCR (sem tag `latest`), executa Trivy antes de publicar e inclui SBOM e proveniência. **Esses workflows ainda precisam de um ensaio real por tag**; testes de PR não exercitam a publicação.

## Critérios para produção

1. CI e análise de segurança aprovados no commit da versão.
2. Testes de concorrência e carga com Redis.
3. Revisão de autenticação e isolamento entre clientes.
4. Testes de falha de rede e *failover*.
5. Controle de cardinalidade e consumo de memória.
6. HTTPS, isolamento de rede e proteção administrativa.
7. Metas de desempenho verificadas em infraestrutura representativa.
8. Plano de rollback e procedimentos operacionais revisados.

A aprovação dos testes automatizados, isoladamente, não comprova prontidão para produção.
