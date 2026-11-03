# Atualizações de dependências e SonarQube em PRs automáticos

## Atualizações integradas por branch confiável

No ciclo de manutenção de novembro de 2026 foram propostas estas atualizações de dependência:

- `actions/checkout` de v4 para **v7.0.1** (referência SHA imutável).
- `actions/setup-java` de v4 para **v6.1.0** (referência SHA imutável).
- `org.jacoco:jacoco-maven-plugin` de 0.8.14 para **0.8.15**.

As versões major das actions podem ter requisitos novos para self-hosted runners; validar o runner antes de migrar fora dos runners hospedados pelo GitHub.

## Por que PRs do Dependabot podem reprovar no SonarQube?

Workflows iniciados pelo `dependabot[bot]` não recebem automaticamente os secrets configurados em **Actions**. O SonarQube exige `SONAR_TOKEN` e falha na etapa de validação caso esteja ausente. Isso **não significa** que os testes Java reprovaram.

Se forem usados PRs do Dependabot para integrar atualizações, configure `SONAR_TOKEN` em **Settings → Secrets and variables → Dependabot → Secrets** com token de análise **limitado ao projeto**. Defina também `SONAR_PROJECT_KEY` e `SONAR_ORGANIZATION` como variables de repositório, conforme [SonarQube Cloud](sonarqube-cloud.md). Não copie tokens em issues, logs ou arquivos.

Antes do merge de cada PR do Dependabot, confirme que o workflow SonarQube foi realmente executado com **success**, não apenas **skipped**. Como alternativa temporária e auditável, replique exatamente as alterações em uma branch confiável, execute todas as verificações na branch e mescle apenas após aprovação completa. Mantenha rastreabilidade para os PRs originais.

Não troque `pull_request` por `pull_request_target` para contornar a ausência de secrets em código não confiável: executar o código do PR com token privilegiado pode comprometer o repositório.

## Observações

- A integração de dependências **não** ativa branch protection, Dependency Review, infraestrutura, backups nem autoriza produção.
- O Quality Gate precisa passar no SHA final da `main` e no SHA usado para publicação.
- Um PR automático com checks vermelhos nunca deve ser mesclado apenas porque a alteração parece pequena.
