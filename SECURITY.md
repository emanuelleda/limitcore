# Política de segurança

O **LimitCore** é um projeto em evolução e **não possui aprovação formal para uso em produção exposta à internet**.

## Como relatar vulnerabilidades

Prefira a funcionalidade de relato privado de vulnerabilidades do GitHub, caso esteja habilitada no repositório. Evite divulgar detalhes de exploração em *issues* públicas.

## Proteções implementadas

- A API exige uma chave no cabeçalho `X-API-Key`.
- A configuração opcional `LIMITCORE_TENANTS` associa credenciais a tenants e isola as chaves de quota no Redis.
- Sem chave configurada no servidor, as solicitações não são autorizadas.
- O cliente não pode alterar a quota por meio do corpo da requisição.
- Os identificadores recebidos são transformados em hash SHA-256 antes de compor as chaves no Redis.
- O Redis local, no Docker Compose, utiliza porta vinculada ao loopback.
- Falhas de Redis não produzem uma autorização positiva automática.
- O endpoint Prometheus não é exposto por padrão.
- O perfil `production` exige credenciais configuradas, TLS para Redis e estabelece limites HTTP/Tomcat; o CI verifica a recusa de Redis sem TLS.
- A imagem executa sem privilégios e é analisada com Trivy; vulnerabilidades HIGH/CRITICAL corrigíveis impedem publicação pelo workflow preparado.

## Riscos e limitações

- O modo legado ainda permite uma chave compartilhada; o modo multitenant utiliza configuração estática; capacidades individuais podem ser configuradas, mas os períodos são globais. O limite `LIMITCORE_MAX_ACTIVE_KEYS` controla a cardinalidade de identificadores ativos por tenant em Redis.
- A rotação gradual de credenciais pode aceitar duas chaves temporárias por tenant via `LIMITCORE_TENANTS="tenant=antiga|nova"`; revogação dinâmica não é implementada: remova a chave antiga e reinicie todas as instâncias.
- A API limita o corpo JSON de decisão a 1 KiB (inclusive em transferências chunked), o tamanho da chave de autenticação e a cardinalidade ativa por tenant. A borda ainda exige rate limiting por origem/IP, limite global de conexões, filtros de tráfego e monitoramento.
- Uma troca de primário no Redis pode causar perda de incrementos recentes.
- Não foi concluída uma auditoria independente de segurança nem uma avaliação operacional de produção.

## Recomendações de implantação

Utilize HTTPS, gerenciamento seguro de segredos, isolamento de rede, autenticação na borda e restrição dos endpoints administrativos. Nunca inclua credenciais no repositório.
