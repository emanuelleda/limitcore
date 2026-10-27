# Operação, monitoramento e resposta a incidentes

## Ambiente local

Inicie o Redis com `docker compose up -d` e execute a aplicação com `mvn spring-boot:run`.

O repositório inclui configurações opcionais do Prometheus e Jaeger em `monitoring/compose.yaml`. O endpoint `/actuator/prometheus` fica **desabilitado para exposição web por padrão**. Habilite-o somente em rede confiável, por exemplo com `MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE=health,info,prometheus`, e proteja o acesso administrativo.

## Indisponibilidade do Redis

O LimitCore não concede uma decisão positiva quando não consegue consultar o Redis. A API pode retornar erro HTTP 5xx ou sofrer *timeout*, de acordo com a falha de rede. Os tempos limites padrão de conexão e comando são `2s`, configuráveis via `REDIS_CONNECT_TIMEOUT` e `REDIS_COMMAND_TIMEOUT`. Os consumidores precisam tratar esse resultado como falha ou decisão desconhecida, seguindo sua política de segurança.

## Troca de primário e recuperação

Scripts Lua são atômicos no primário em que são executados. A replicação assíncrona pode perder atualizações recentes durante um *failover*. Avalie esse risco antes de utilizar quotas estritas.

## Teste automatizado de falha e recuperação

O workflow `API Smoke and Redis Recovery` executa um teste curto de k6 e derruba temporariamente o contêiner Redis. Ele exige resposta 5xx ou indisponibilidade de transporte durante a falha e HTTP 200 após o serviço reiniciar. Esse teste verifica **parada e retorno de um nó**, não replicação, Sentinel, Cluster, persistência de contadores nem perda de comandos após eleição de primário.

## Traces locais

Execute `docker compose -f monitoring/compose.yaml up -d jaeger`, inicie o LimitCore e consulte o serviço `limitcore` em http://localhost:16686. O endpoint OTLP é configurado por `LIMITCORE_OTLP_ENDPOINT` (padrão `http://localhost:4318/v1/traces`). A interface Jaeger e a porta OTLP estão vinculadas somente a 127.0.0.1 no ambiente local.

## Mudança de versão e chaves Redis

O controle de cardinalidade usa novas *hash tags* Redis por tenant. **A implantação dessa versão reinicia quotas em andamento**, pois as chaves anteriores não são migradas. Não misture versões antigas e novas por períodos longos: elas não compartilharão os mesmos contadores. Planeje janela de mudança, testes de retorno, observação do Redis e procedimento de rollback.

## Segurança operacional

- Armazene `LIMITCORE_API_KEY` em um gerenciador de segredos.
- Utilize HTTPS na entrada da aplicação.
- Restrinja o acesso ao Redis e aos endpoints administrativos.
- Prefira credenciais distintas por tenant; use `LIMITCORE_TENANTS="tenant=chaveAntiga|chaveNova"` para rotação gradual e remova a chave antiga por configuração/novo deploy.
- Use `LIMITCORE_MAX_ACTIVE_KEYS` de acordo com a cardinalidade esperada; ele controla a quantidade de chaves ativas por tenant e pode negar clientes novos quando esgotado.
- Não registre segredos em logs.

## Procedimentos de diagnóstico

| Sintoma | Verificações recomendadas |
| --- | --- |
| Aumento de erros 5xx | Conectividade, saúde e latência do Redis |
| Aumento de respostas 401 | Distribuição e validade da chave de API |
| Crescimento de memória | Cardinalidade de chaves e uso da janela deslizante |
| Lentidão | Latência de rede, CPU, Redis e saturação da aplicação |

## Checklist antes de produção

- [ ] CI e CodeQL aprovados no commit de publicação
- [ ] Dependências e alertas de segurança revisados
- [ ] Testes de carga executados em ambiente representativo
- [ ] Exercício de *failover* documentado
- [ ] Segredos e redes protegidos
- [ ] Acesso às métricas restrito
- [ ] Procedimento de rollback validado
