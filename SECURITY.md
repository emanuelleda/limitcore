# Política de segurança

O **LimitCore** é um projeto em evolução e **não possui aprovação formal para uso em produção exposta à internet**.

## Como relatar vulnerabilidades

Prefira a funcionalidade de relato privado de vulnerabilidades do GitHub, caso esteja habilitada no repositório. Evite divulgar detalhes de exploração em *issues* públicas.

## Proteções implementadas

- A API exige uma chave no cabeçalho `X-API-Key`.
- Sem chave configurada no servidor, as solicitações não são autorizadas.
- O cliente não pode alterar a quota por meio do corpo da requisição.
- Os identificadores recebidos são transformados em hash SHA-256 antes de compor as chaves no Redis.
- O Redis local, no Docker Compose, utiliza porta vinculada ao loopback.
- Falhas de Redis não produzem uma autorização positiva automática.
- O endpoint Prometheus não é exposto por padrão.

## Riscos e limitações

- A autenticação utiliza uma chave compartilhada, sem isolamento multitenant.
- Ainda não há rotação ou revogação individual de credenciais.
- Não existe controle completo de cardinalidade de chaves ou tamanho das requisições na borda.
- Uma troca de primário no Redis pode causar perda de incrementos recentes.
- Não foi concluída uma auditoria independente de segurança nem uma avaliação operacional de produção.

## Recomendações de implantação

Utilize HTTPS, gerenciamento seguro de segredos, isolamento de rede, autenticação na borda e restrição dos endpoints administrativos. Nunca inclua credenciais no repositório.
