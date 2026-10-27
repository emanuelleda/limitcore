# Como contribuir

Obrigado pelo interesse em contribuir com o **LimitCore**!

## Fluxo de contribuição

1. Abra uma *issue* explicando o problema, a melhoria ou a funcionalidade proposta.
2. Crie uma branch com escopo bem definido.
3. Implemente a alteração e inclua testes automatizados quando houver mudança de comportamento.
4. Execute `mvn verify` e informe eventuais testes adicionais com Redis.
5. Envie um *pull request* descrevendo a solução, os testes realizados e os possíveis impactos.

## Boas práticas

- Priorize código legível, alterações pequenas e compatibilidade com a API existente.
- Mudanças nos algoritmos devem explicar os efeitos sobre concorrência, atomicidade e falhas do Redis.
- Atualize o README e os documentos técnicos sempre que alterar o comportamento público.
- Nunca publique chaves de API, senhas, tokens, dados pessoais ou credenciais de infraestrutura.

Falhas de segurança devem ser comunicadas de forma privada, conforme a [política de segurança](SECURITY.md).
