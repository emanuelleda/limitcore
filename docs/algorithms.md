# Algoritmos de limitação de requisições

O LimitCore disponibiliza três algoritmos. A escolha e a capacidade são definidas por variáveis de ambiente no servidor. Toda consulta exige uma chave válida no cabeçalho `X-API-Key`.

## Janela fixa (`fixed-window`)

Utiliza um contador Redis com expiração iniciada na primeira solicitação aceita. Um script Lua executa a verificação e o incremento de forma atômica.

**Vantagem:** implementação simples e baixo consumo de memória.

**Limitação:** pode permitir picos de tráfego na transição entre janelas.

## Balde de tokens (`token-bucket`)

Armazena a quantidade de tokens disponíveis e o instante da última atualização. O reabastecimento utiliza o relógio do Redis.

**Vantagem:** permite picos controlados e recuperação gradual da capacidade.

**Limitação:** o comportamento depende da taxa de reposição e da capacidade configuradas.

## Janela deslizante (`sliding-window`)

Mantém registros das solicitações aceitas em um conjunto ordenado do Redis, removendo os eventos expirados. Um contador auxiliar fornece identificadores únicos.

**Vantagem:** controla o número de solicitações ao longo de uma janela móvel.

**Limitação:** consome memória proporcional ao número de solicitações aceitas por chave.

## Configuração

```bash
export LIMITCORE_API_KEY='substitua-por-um-segredo-aleatorio-longo'
export LIMITCORE_ALGORITHM=token-bucket
export LIMITCORE_CAPACITY=100
export LIMITCORE_WINDOW_SECONDS=60
```

## Garantias e limites

A atomicidade dos scripts Lua vale para um único primário Redis. O projeto não oferece consistência global entre regiões. Em caso de indisponibilidade do Redis, a API responde com erro de servidor, e não com uma decisão positiva. O consumidor deve tratar explicitamente esse cenário.
