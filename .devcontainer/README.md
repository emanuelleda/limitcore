# Executar LimitCore temporariamente no GitHub

O [GitHub Codespaces](https://docs.github.com/pt/codespaces) permite **demonstrar a API no navegador, usando um ambiente do próprio GitHub**, sem instalar nada na VPS da empresa.

**Limitação importante:** GitHub Codespaces é um ambiente de desenvolvimento, **não hospedagem 24/7**. Ele para após inatividade; o endereço encaminhado pode mudar. O GitHub Actions continua executando CI, testes e análise de segurança, mas não mantém um servidor permanentemente no ar. Não use esta configuração para clientes ou dados reais.

## Iniciar

1. No [repositório LimitCore](https://github.com/emanuelleda/limitcore), abra **Code → Codespaces → Create codespace on main**.
2. O Codespaces prepara **Java 25 + Maven + Redis** e inicia a API em uma sessão destacada de `tmux`, com uma credencial temporária criada dentro do Codespace. Se já tiver um Codespace anterior à correção de novembro, primeiro execute **Command Palette → Codespaces: Rebuild Container** para instalar o `tmux`.
3. No terminal **dentro do Codespaces**, execute:
   ```bash
   bash .devcontainer/start-demo.sh
   bash .devcontainer/start-demo.sh --status
   ```
   O primeiro comando aguarda até três minutos por uma API saudável; em uma primeira instalação o Maven pode precisar de mais tempo. Consulte o log sem mostrar a chave:
   ```bash
   tail -n 80 ~/.local/state/limitcore-demo/app.log
   ```
   O status deve indicar **liveness UP** e **readiness UP**. O script não interpreta a existência de um PID como prova de que a API iniciou.
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

## Diagnóstico quando a porta 8080 recusa conexão

O indicador `process already running` das versões anteriores verificava apenas um PID e podia deixar a impressão de que a API estava saudável. A configuração atual usa uma sessão independente de `tmux` e valida tanto liveness como readiness.

```bash
cd /workspaces/limitcore
bash .devcontainer/start-demo.sh --status
tail -n 100 ~/.local/state/limitcore-demo/app.log
tmux list-sessions
```

Se o Maven tiver encerrado com erro, o diagnóstico mostra a saída. Para reiniciar **somente a demonstração do LimitCore**:

```bash
bash .devcontainer/start-demo.sh --restart
```

Isso não modifica a VPS nem os bancos de dados externos. O Redis da demonstração é efêmero. Não execute os comandos no notebook ou na VPS: o arquivo de credencial e a porta 8080 são internos ao Codespace.

## Segurança e custos

- Chave gerada aleatoriamente dentro do Codespace, fora do repositório, nunca versionada. Não use a chave de produção.
- Redis é **temporário**, sem password e sem persistência, **somente na rede interna dos contêineres**. A porta 6379 não é encaminhada.
- Porta 8080 é privada por padrão e requer login GitHub na URL externa. Nunca a torne pública com a chave de demonstração.
- O Codespace pode consumir a franquia ou gerar custo conforme o plano. Pare-o quando não estiver usando.
- Fechar a aba não garante a parada imediata; após inatividade o Codespace é suspenso.
- Para disponibilizar API pública **24/7** posteriormente será necessário hospedar fora do Codespaces, com Redis TLS, HTTPS, backups, segredos e monitoramento; veja [Go/No-Go](../docs/release-go-no-go.md).
