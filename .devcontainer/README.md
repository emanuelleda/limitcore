# Executar LimitCore temporariamente no GitHub

O [GitHub Codespaces](https://docs.github.com/pt/codespaces) permite **demonstrar a API no navegador, usando um ambiente do próprio GitHub**, sem instalar nada na VPS da empresa.

**Limitação importante:** GitHub Codespaces é um ambiente de desenvolvimento, **não hospedagem 24/7**. Ele para após inatividade; o endereço encaminhado pode mudar. O GitHub Actions continua executando CI, testes e análise de segurança, mas não mantém um servidor permanentemente no ar. Não use esta configuração para clientes ou dados reais.

## Iniciar

1. No [repositório LimitCore](https://github.com/emanuelleda/limitcore), abra **Code → Codespaces → Create codespace on main**.
2. O Codespaces prepara **Java 25 + Maven + Redis** e executa a API automaticamente com credencial temporária criada dentro do Codespace.
3. Aguarde o Maven terminar a primeira inicialização; no terminal do Codespace, consulte:
   ```bash
   tail -f ~/.local/state/limitcore-demo/app.log
   ```
   `Started LimitCoreApplication` indica que a aplicação iniciou.
4. Na aba **Ports**, abra a porta **8080**. Ela deve continuar **Private**; não use `Public`.

## Testar

No terminal do Codespace (sem copiar a chave para chats ou arquivos do projeto):

```bash
export LIMITCORE_API_KEY="$(cat ~/.local/state/limitcore-demo/api-key)"
curl -fsS http://localhost:8080/actuator/health/readiness
curl -fsS -X POST http://localhost:8080/v1/limits/check \
  -H "X-API-Key: $LIMITCORE_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"key":"demo"}'
```

Resposta esperada do segundo comando: JSON com `allowed` e `algorithm`. O algoritmo de demonstração é `token-bucket` e a quota é compartilhada pelo tenant.

Quando a aplicação for reiniciada junto com o Codespace, o hook `postStartCommand` verifica se ela já está funcionando e tenta iniciá-la novamente se necessário.

## Segurança e custos

- Chave gerada aleatoriamente dentro do Codespace, fora do repositório, nunca versionada. Não use a chave de produção.
- Redis é **temporário**, sem password e sem persistência, **somente na rede interna dos contêineres**. A porta 6379 não é encaminhada.
- Porta 8080 é privada por padrão e requer login GitHub na URL externa. Nunca a torne pública com a chave de demonstração.
- O Codespace pode consumir a franquia ou gerar custo conforme o plano. Pare-o quando não estiver usando.
- Fechar a aba não garante a parada imediata; após inatividade o Codespace é suspenso.
- Para disponibilizar API pública **24/7** posteriormente será necessário hospedar fora do Codespaces, com Redis TLS, HTTPS, backups, segredos e monitoramento; veja [Go/No-Go](../docs/release-go-no-go.md).
