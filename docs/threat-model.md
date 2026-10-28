# Modelo de ameaças — LimitCore

> Escopo: API REST de decisão de rate limiting, instâncias Java, armazenamento Redis e configuração de credenciais. Este documento não constitui auditoria independente nem certificação.

## Limites de confiança

1. **Cliente → API:** dados não confiáveis, incluindo `X-API-Key`, identificador `key`, origem e frequência das requisições. Exigir TLS no ingress e limites de tráfego fora da API.
2. **API → Redis:** conexão privada e autenticada. Scripts Lua são estáticos e versionados; nomes de chaves derivam de hashes. Em produção, exigir TLS e segmentação de rede.
3. **Operador → configuração:** `LIMITCORE_API_KEY`, `LIMITCORE_TENANTS` e parâmetros de quota são segredos/configuração operacional. Nunca versionar valores reais.
4. **CI → artefatos:** builds, imagens e releases dependem das permissões do workflow e da integridade das dependências.

## Principais ameaças e controles

| Ameaça | Impacto | Controle presente | Limitação / ação necessária |
| --- | --- | --- | --- |
| Reutilização ou vazamento de API Key | Acesso indevido à quota | SHA-256 pré-computado e comparação dos digests; credenciais distintas entre tenants | TLS no ingress, cofre, auditoria, revogação por nova configuração e reinício; automatizar rotação |
| Enumeração de identificadores de quota | Explosão de memória Redis | Identificadores com SHA-256, limite de entradas ativas por tenant e expiração atômica Lua | Capacidade de memória e número de tenants ainda precisam de benchmark; limitar tráfego na borda |
| Rajadas concorrentes | Ultrapassagem da quota | Redis Lua atômico, testes de concorrência | Failover pode perder estado replicado; não utilizar como mecanismo único de cobrança financeira |
| Redis indisponível | Decisão indevida ou indisponibilidade | Erro HTTP 503 (*fail closed*), health/readiness, teste de recuperação | Dimensionamento HA real, alertas e acordo de disponibilidade ficam a cargo do operador |
| Redis Sentinel failover | Perda de incrementos não replicados | Simulação CI com três sentinels | Replicação assíncrona: consistência eventual em failover; validar a topologia de produção |
| Payload malformado / volumoso | CPU, memória ou exploração de parsers | Bean Validation, limite de corpo JSON de 1 KiB, controle de cabeçalhos | WAF / gateway deve limitar conexões, origem e taxa de autenticação |
| Exposição de métricas e traces | Vazamento de metadados | Prometheus não exposto por padrão; métricas sem labels de tenant/chave | Restringir redes e acesso ao coletor; verificar retenção e políticas de privacidade |
| Mudança incompatível de formato Redis | Reset inesperado de quota | Documentação de migração e rollback | Fazer rollout coordenado e verificar efeitos durante janela de transição |
| Artefato comprometido | Execução de código vulnerável | CodeQL, Dependabot, Trivy, SBOM e CI | Auditoria independente, revisão de dependências e validação de artefatos publicados |

## Cenários de abuso a testar no staging

- 401 para credencial ausente, inválida ou excessivamente longa, sem consulta ao Redis.
- Um tenant não altera a quota de outro, mesmo quando ambos usam o mesmo identificador.
- Rejeição de novas chaves quando o teto de chaves ativas for alcançado, inclusive sob alta concorrência.
- Reutilização da mesma chave após expiração legítima do estado.
- HTTP 503, sem decisão positiva, quando Redis não responder.
- Troca de credencial antiga por nova, retirada da antiga e reinício sem acesso residual.
- Falha do primário Redis, eleição Sentinel, reconexão e medição de decisões durante a indisponibilidade.
- Tráfego volumoso com origem distribuída, acompanhado de p95/p99, CPU e memória do Redis.

## Critérios de risco residual

**Não liberar para produção** sem confirmar: TLS e autenticação Redis, HTTPS do ingress, configuração de segredos em cofre, orçamento de memória, cenários de carga, alertas com responsáveis, restore/rollback testados e aprovação independente de segurança. Uma verificação verde no GitHub Actions não prova essas propriedades em infraestrutura real.

Referências: [prontidão para produção](production-readiness.md), [operação](operations.md), [segurança](../SECURITY.md).
