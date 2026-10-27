# ADR-0001 — Uso de scripts Lua no Redis

**Estado:** aceito para o protótipo.

## Contexto

Múltiplas instâncias da API precisam consultar e atualizar limites compartilhados sem depender de bloqueios mantidos pela aplicação.

## Decisão

Utilizar scripts Lua executados no Redis para verificar e atualizar quotas de maneira atômica. Os algoritmos de janela deslizante e balde de tokens usam o relógio do próprio Redis. Chaves relacionadas utilizadas pelo mesmo script são agrupadas no mesmo *hash slot* para compatibilidade com Redis Cluster.

## Consequências

A atomicidade é garantida durante a execução em um único primário Redis, mas não oferece consistência entre regiões. Uma troca de primário pode perder atualizações já reconhecidas. A janela deslizante armazena registros proporcionais ao volume aceito por chave.

Antes do uso em produção, ainda são necessários controles de cardinalidade, testes de carga e avaliação do comportamento em falhas.
