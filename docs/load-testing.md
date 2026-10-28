# Guia de benchmarking e validação de desempenho

O LimitCore possui dois tipos de testes de carga: **smoke automatizado** e **benchmark configurável**. Não confunda resultados de execução em runners efêmeros com metas de capacidade para produção.

## Smoke automatizado

O workflow `API Smoke and Redis Recovery`:

1. Compila a aplicação e inicia um Redis local em um contêiner.
2. Executa `benchmarks/smoke.js` via k6 durante 10 segundos com 2 usuários virtuais.
3. Interrompe o Redis e verifica que a API não fornece uma decisão positiva durante a falha (erro 5xx ou *timeout* de transporte).
4. Reinicia o Redis e confirma que a API volta a responder HTTP 200.

O teste de parada/reinício **não** cobre failover Sentinel/Cluster ou persistência dos contadores.

## Simulação Sentinel no CI

O workflow `Redis Sentinel Failover` configura um primário e uma réplica Redis com **três sentinels e quórum dois**, inicia a API conectada ao Sentinel, derruba o primário, aguarda a promoção da réplica e verifica que a API volta a responder. Essa validação automatizada cobre o fluxo básico de eleição/reconexão. Não representa execução em múltiplos hosts, partição de rede, zonas de disponibilidade ou risco de perda de incrementos por replicação assíncrona.

## Benchmark manual

Inicie Redis e API e configure a credencial. Em um terminal com k6 instalado, execute:

```bash
LIMITCORE_API_KEY="$LIMITCORE_API_KEY" \
LIMITCORE_BENCH_VUS=25 \
LIMITCORE_BENCH_DURATION=60s \
LIMITCORE_BENCH_KEYS=500 \
LIMITCORE_BENCH_P95_MS=500 \
k6 run benchmarks/k6.js
```

Parâmetros:

| Variável | Padrão | Objetivo |
| --- | --- | --- |
| `LIMITCORE_URL` | `http://localhost:8080/v1/limits/check` | Endpoint |
| `LIMITCORE_BENCH_VUS` | `10` | Usuários virtuais |
| `LIMITCORE_BENCH_DURATION` | `30s` | Duração |
| `LIMITCORE_BENCH_KEYS` | `100` | Diversidade de identificadores |
| `LIMITCORE_BENCH_P95_MS` | `500` | Limiar experimental de latência |

A consulta usa o cabeçalho `X-API-Key` e o identificador `benchmark-<n>`. As métricas `limitcore_allowed_ratio` e `limitcore_denied_ratio` diferenciam aceitação e bloqueio; o benchmark mede **decisões**, não respostas HTTP 429.

Ajuste `LIMITCORE_MAX_ACTIVE_KEYS` e a capacidade da quota antes do teste, para evitar que a maior parte dos resultados corresponda somente à recusa de novos identificadores ou a quotas esgotadas.

## Registro de resultados

Registre em cada execução:

- SHA exato, versão, algoritmo, capacidade, período, máximo de identificadores e número de tenants.
- CPU, memória, topologia, versão do Redis, latência de rede e contexto do ambiente.
- VUs, taxa de chegada, diversidade de identificadores, tempo total, requisições/segundo e p50/p95/p99.
- Taxa de `allowed=true`, recusas, 5xx, *timeouts*, disponibilidade e uso de memória Redis.
- Repetições e flutuação dos resultados. Estabeleça metas antes de testar.

Não publique números de throughput ou capacidade máxima sem guardar esses dados. Testes de carga relevantes devem ser repetidos em uma infraestrutura semelhante à de produção.

## Testes ainda necessários para certificação operacional

- Failover real com Redis Sentinel ou Cluster, incluindo janelas de replicação.
- Testes de recuperação diante de atraso e perda de pacotes, e falhas parciais.
- Concorrência e cardinalidade elevada entre múltiplas instâncias e tenants.
- Proteção de dados de segredos, TLS, autenticação do Redis, limites de recursos e revisão externa.
