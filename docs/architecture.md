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
- **Autenticação:** suporta uma credencial compartilhada legada ou credenciais estáticas separadas por tenant (até duas durante uma rotação).
- **Algoritmos:** janela fixa, balde de tokens e janela deslizante.
- **Redis:** mantém os contadores e um conjunto ordenado de identificadores ativos por tenant; chaves da mesma organização compartilham um slot no Redis Cluster.
- **Scripts Lua:** executam verificações e alterações do estado de maneira atômica no primário.

## Consistência e disponibilidade

Diferentes instâncias da API podem compartilhar um mesmo Redis. Entretanto, a replicação e o *failover* do Redis não garantem a preservação de todos os incrementos reconhecidos. Não há garantia de consistência entre regiões.

Uma falha de comunicação com o Redis provoca erro, em vez de liberar automaticamente a solicitação.

## Contrato HTTP

O endpoint retorna HTTP 200 tanto para decisões positivas quanto negativas. A aplicação cliente deve verificar o campo `allowed`. O LimitCore não atua como proxy nem aplica HTTP 429 diretamente ao usuário final.

## Considerações operacionais

O armazenamento da janela deslizante cresce com a quantidade de eventos e chaves ativas. A implementação agrupa chaves de um mesmo tenant em uma *hash tag* Redis, garantindo que as operações multichave sejam executadas no mesmo slot. O limite `LIMITCORE_MAX_ACTIVE_KEYS` é verificado atomicamente junto com a decisão de quota. Isso cria um limite previsível de cardinalidade, mas concentra o processamento de um tenant no mesmo slot.

**Migração de estado:** o novo layout `limitcore:{hash-do-tenant}:hash-da-chave` não reutiliza o layout anterior; a atualização reinicia quotas ativas. Um limite de cardinalidade atingido retorna `allowed=false`, assim como uma quota esgotada. Ainda não há políticas de memória globais, redistribuição entre slots do mesmo tenant ou identidade corporativa completa.

Consulte [algoritmos](algorithms.md), [operações](operations.md) e [segurança](../SECURITY.md).
