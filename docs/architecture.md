# Arquitetura do LimitCore

## Fluxo de uma solicitação

```text
Aplicação cliente
      |
      | POST /v1/limits/check + X-API-Key
      v
API Spring Boot
      |
      | Validação, autenticação e quota configurada
      v
Script Lua executado no Redis
      |
      | Decisão atômica
      v
Resposta JSON: allowed = true/false
```

## Componentes

- **API REST:** recebe a identificação da chave lógica e retorna uma decisão.
- **Autenticação inicial:** valida uma chave de API compartilhada.
- **Algoritmos:** janela fixa, balde de tokens e janela deslizante.
- **Redis:** mantém o estado compartilhado entre instâncias da aplicação.
- **Scripts Lua:** executam verificações e alterações do estado de maneira atômica no primário.

## Consistência e disponibilidade

Diferentes instâncias da API podem compartilhar um mesmo Redis. Entretanto, a replicação e o *failover* do Redis não garantem a preservação de todos os incrementos reconhecidos. Não há garantia de consistência entre regiões.

Uma falha de comunicação com o Redis provoca erro, em vez de liberar automaticamente a solicitação.

## Contrato HTTP

O endpoint retorna HTTP 200 tanto para decisões positivas quanto negativas. A aplicação cliente deve verificar o campo `allowed`. O LimitCore não atua como proxy nem aplica HTTP 429 diretamente ao usuário final.

## Considerações operacionais

O armazenamento da janela deslizante cresce com a quantidade de eventos e chaves ativas. Em Redis Cluster, as chaves utilizadas pelo mesmo script precisam compartilhar o mesmo *hash slot*. A autenticação atual não equivale a um sistema completo de identidade multitenant.

Consulte [algoritmos](algorithms.md), [operações](operations.md) e [segurança](../SECURITY.md).
