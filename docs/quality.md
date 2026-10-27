# Qualidade, testes e critérios de publicação

## Testes automatizados

O GitHub Actions executa `mvn verify`, incluindo testes unitários com JUnit/Mockito e testes de integração com Redis por meio do Testcontainers. O projeto possui um teste de concorrência para o algoritmo de janela fixa.

O JaCoCo gera relatórios de cobertura, disponibilizados como artefatos do pipeline.

## Segurança e dependências

O workflow CodeQL realiza análise estática. A revisão de dependências é executada em *pull requests*, enquanto o Dependabot propõe atualizações periódicas.

## SonarQube

O arquivo `sonar-project.properties` define caminhos básicos de análise. Para utilizar SonarQube ou SonarCloud, ainda é necessário configurar a organização, a autenticação e a integração com o repositório. Não publique tokens. **Uma aprovação de quality gate do SonarQube ainda não foi demonstrada.**

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
