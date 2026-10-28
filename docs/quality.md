# Qualidade, testes e critérios de publicação

## Testes automatizados

O GitHub Actions executa `mvn verify`, incluindo testes unitários com JUnit/Mockito e testes de integração com Redis por meio do Testcontainers. O projeto cobre concorrência para a janela fixa e registro limitado de identificadores; há testes de isolamento de tenants e expiração de registros no Redis.

O JaCoCo gera relatórios de cobertura, disponibilizados como artefatos do pipeline. O CI também gera e publica um SBOM CycloneDX compatível com Java 25.

## Segurança e dependências

O workflow CodeQL realiza análise estática. A revisão automática de dependências em *pull requests* depende da ativação do Dependency graph e da variável `LIMITCORE_DEPENDENCY_REVIEW_ENABLED=true`; sem elas, esse job é ignorado. O Dependabot propõe atualizações periódicas.

## SonarQube

O workflow opcional `.github/workflows/sonar.yml` executa testes, cobertura e análise quando existem `SONAR_TOKEN` (secret) e `SONAR_PROJECT_KEY` (variable). Configure também `SONAR_ORGANIZATION` para SonarCloud e, quando aplicável, `SONAR_HOST_URL`. Se não houver credenciais, o workflow informa que a análise foi ignorada. O arquivo `sonar-project.properties` define os caminhos de análise. Não publique tokens. **Uma aprovação de quality gate do SonarQube ainda não foi demonstrada.**

## Smoke, benchmark e dependências

O workflow `API Smoke and Redis Recovery` executa `benchmarks/smoke.js` com k6, valida o comportamento em uma parada de Redis e verifica retorno após reinício. Os limiares deste teste são de **sanidade do endpoint**, não metas de escala para produção. O `benchmarks/k6.js` aceita quantidade de VUs, duração, número de identificadores e limiar p95 parametrizados para execuções controladas. Consulte [guia de benchmark](load-testing.md). Ainda não há resultados de carga representativa publicados.

A ação `dependency-review` depende de o **Dependency graph** estar habilitado nas configurações de segurança do GitHub. Enquanto isso não estiver configurado, o job correspondente só é ativado quando a variável do repositório `LIMITCORE_DEPENDENCY_REVIEW_ENABLED=true` for definida. CodeQL, CI e Dependabot têm configuração separada.

## Publicação de versões

O workflow `Release` é acionado por tags no formato `v*`. Ele executa `mvn verify`, gera um inventário de componentes de software (SBOM CycloneDX) e tenta publicar o JAR e os arquivos SBOM em uma GitHub Release. A execução de uma publicação real ainda precisa ser verificada antes de considerar a automação validada.

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
