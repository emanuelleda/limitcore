# Integração SonarQube Cloud

O workflow [SonarQube](../.github/workflows/sonar.yml) executa `mvn verify`, publica análise e aguarda o Quality Gate. A análise é disparada em push na `main`, PRs internos e manualmente. PRs de forks não recebem o token.

## Configuração obrigatória no GitHub

Em **Settings → Secrets and variables → Actions** configure:

| Tipo | Nome | Valor |
| --- | --- | --- |
| Secret | `SONAR_TOKEN` | Token de análise gerado no SonarQube Cloud (nunca envie para o repositório) |
| Variable | `SONAR_PROJECT_KEY` | **Project Key** exata exibida no SonarQube Cloud |
| Variable | `SONAR_ORGANIZATION` | **Organization Key** exata, não o nome visível da organização |
| Variable opcional | `SONAR_HOST_URL` | `https://sonarcloud.io` (ou deixe vazio para Cloud) |

**Importante:** `SONAR_PROJECT_KEY` e `SONAR_ORGANIZATION` são valores distintos. Renomear o projeto não corrige a falta da chave da organização. Consulte a Organization Key na administração da organização do SonarQube Cloud.

Após configurar, execute **Actions → SonarQube → Run workflow**, selecione `main` e abra o job para verificar que a etapa de validação e o Quality Gate passaram.

### Diagnóstico

- `You must define ... sonar.organization`: variável `SONAR_ORGANIZATION` vazia ou ausente.
- `Project not found` ou `Not authorized`: confira token, permissões, projeto e organização.
- `Quality Gate failed`: consulte os achados no SonarQube Cloud, corrija o código e rode novamente.

Para um servidor **SonarQube auto-hospedado**, defina `SONAR_HOST_URL` como a URL do servidor; a organização pode não ser necessária.

Não marque a integração como concluída até que um workflow real passe e o Quality Gate seja aprovado.
