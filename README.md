# LimitCore

[![CI](https://github.com/emanuelleda/limitcore/actions/workflows/ci.yml/badge.svg)](https://github.com/emanuelleda/limitcore/actions/workflows/ci.yml)
[![Segurança](https://github.com/emanuelleda/limitcore/actions/workflows/security.yml/badge.svg)](https://github.com/emanuelleda/limitcore/actions/workflows/security.yml)
![Licença MIT](https://img.shields.io/badge/licen%C3%A7a-MIT-blue)

**API de controle distribuído de requisições (rate limiting)** desenvolvida com Java 25, Spring Boot e Redis.

O LimitCore permite que aplicações consultem se uma solicitação deve ser autorizada conforme uma quota configurada no servidor. Instâncias diferentes da API compartilham o estado no Redis, usando scripts Lua para operações atômicas.

> **Estado:** projeto open source em evolução. Os testes automatizados não substituem auditoria de segurança, testes de carga e validação operacional. Não há certificação de prontidão para produção.

## Tecnologias

- Java 25 e Spring Boot 3.5
- Redis e scripts Lua
- Maven, JUnit e Mockito
- Testcontainers para testes de integração
- Docker e Docker Compose
- GitHub Actions, CodeQL, Dependabot e JaCoCo
- Contrato OpenAPI, recursos iniciais de Prometheus/Grafana e benchmark k6

## Algoritmos disponíveis

| Algoritmo | Configuração | Funcionamento |
| --- | --- | --- |
| Janela fixa | `fixed-window` | Contador com prazo de expiração no Redis |
| Balde de tokens | `token-bucket` | Reposição gradual de tokens usando o relógio do Redis |
| Janela deslizante | `sliding-window` | Registra solicitações aceitas em um conjunto ordenado |

Veja [detalhes dos algoritmos](docs/algorithms.md).

## Pré-requisitos

Java 25, Maven 3.9 ou superior e Docker com Docker Compose.

## Como executar

Clone o repositório e entre na pasta:

```bash
git clone https://github.com/emanuelleda/limitcore.git
cd limitcore
```

Inicie o Redis local:

```bash
docker compose up -d
```

Configure a chave de acesso e os limites:

```bash
export LIMITCORE_API_KEY="$(openssl rand -hex 32)"
export LIMITCORE_ALGORITHM=token-bucket
export LIMITCORE_CAPACITY=100
export LIMITCORE_WINDOW_SECONDS=60
```

Inicie a aplicação:

```bash
mvn spring-boot:run
```

### Exemplo de requisição

```bash
curl -X POST http://localhost:8080/v1/limits/check \
  -H "X-API-Key: $LIMITCORE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"key":"cliente-123"}'
```

Exemplo de resposta:

```json
{"allowed":true,"algorithm":"token-bucket"}
```

**Importante:** quando a quota é atingida, a API responde HTTP 200 com `"allowed":false`. Cabe à aplicação consumidora aplicar o bloqueio. Chaves ausentes ou inválidas retornam HTTP 401.

## Variáveis de ambiente

| Variável | Valor padrão | Descrição |
| --- | --- | --- |
| `LIMITCORE_API_KEY` | Vazio | Credencial compartilhada; vazia, nenhuma requisição é autorizada |
| `LIMITCORE_ALGORITHM` | `fixed-window` | Algoritmo utilizado |
| `LIMITCORE_CAPACITY` | `100` | Capacidade da quota |
| `LIMITCORE_WINDOW_SECONDS` | `60` | Período em segundos |
| `REDIS_HOST` | `localhost` | Endereço do Redis |
| `REDIS_PORT` | `6379` | Porta do Redis |

As quotas são definidas pelo servidor, não pelo cliente.

## Testes e qualidade

```bash
mvn verify
```

O pipeline executa testes unitários e de integração com Redis por meio do Testcontainers. O JaCoCo produz relatórios de cobertura; o CodeQL verifica o código e o Dependabot acompanha dependências.

A configuração para SonarQube está presente, mas a análise em uma organização conectada depende de configuração externa.

## Observabilidade e desempenho

Há uma configuração inicial de Prometheus, um dashboard JSON do Grafana e um script k6. O endpoint `/actuator/prometheus` **não é exposto por padrão**; habilite-o apenas em uma rede protegida. Os limites de desempenho do script k6 ainda não foram validados como objetivos de serviço.

## Documentação

- [Arquitetura](docs/architecture.md)
- [Algoritmos](docs/algorithms.md)
- [Contrato OpenAPI](docs/openapi.yaml)
- [Operação e incidentes](docs/operations.md)
- [Qualidade e critérios de publicação](docs/quality.md)
- [Decisão arquitetural: Redis Lua](docs/adr/0001-redis-lua.md)
- [Política de segurança](SECURITY.md)
- [Como contribuir](CONTRIBUTING.md)

## Próximos passos

- [x] Três algoritmos com scripts Lua atômicos
- [x] API Key compartilhada e quotas controladas pelo servidor
- [x] Testes unitários, integração com Redis e teste de concorrência
- [x] CI, CodeQL, Dependabot e cobertura JaCoCo
- [x] Contrato OpenAPI e ferramentas iniciais de observabilidade
- [ ] Autenticação e quotas isoladas por cliente/organização
- [ ] Proteção completa contra excesso de chaves e consumo de memória
- [ ] Tracing distribuído e testes de failover
- [ ] SonarQube conectado e benchmark validado
- [ ] Revisão operacional e de segurança antes de produção

## Licença

Distribuído sob a [licença MIT](LICENSE).
