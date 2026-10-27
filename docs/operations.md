# Operação, monitoramento e resposta a incidentes

## Ambiente local

Inicie o Redis com `docker compose up -d` e execute a aplicação com `mvn spring-boot:run`.

O repositório inclui uma configuração opcional do Prometheus em `monitoring/compose.yaml`. O endpoint `/actuator/prometheus` fica **desabilitado para exposição web por padrão**. Habilite-o somente em rede confiável, por exemplo com `MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE=health,info,prometheus`, e proteja o acesso administrativo.

## Indisponibilidade do Redis

O LimitCore não concede uma decisão positiva quando não consegue consultar o Redis. A API pode retornar erro HTTP 5xx. Os consumidores precisam tratar esse resultado como falha ou decisão desconhecida, seguindo sua política de segurança.

## Troca de primário e recuperação

Scripts Lua são atômicos no primário em que são executados. A replicação assíncrona pode perder atualizações recentes durante um *failover*. Avalie esse risco antes de utilizar quotas estritas.

## Segurança operacional

- Armazene `LIMITCORE_API_KEY` em um gerenciador de segredos.
- Utilize HTTPS na entrada da aplicação.
- Restrinja o acesso ao Redis e aos endpoints administrativos.
- Planeje a rotação de credenciais; o protótipo ainda utiliza uma chave compartilhada.
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
