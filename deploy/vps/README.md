# LimitCore — implantação em VPS com Docker Compose

Esta é uma **opção de implantação de instância única**, não uma arquitetura HA completa. O serviço fica restrito a `127.0.0.1` para ser publicado **somente por um reverse proxy HTTPS confiável**. A produção com alta disponibilidade deve usar múltiplas instâncias, Redis TLS/HA e validações operacionais documentadas em [Go/No-Go](../../docs/release-go-no-go.md).

## Pré-requisitos

- Linux com Docker Engine, Docker Compose **v2**, `jq`, `openssl`, `git` e acesso à imagem publicada no GitHub Container Registry.
- Um **Redis externo já provisionado** (TLS com verificação de certificado, senha, backups e failover conforme SLO), alcançável a partir da VPS. O compose não cria Redis não autenticado.
- Um hostname HTTPS e reverse proxy (Caddy, Nginx ou equivalente) já configurado para encaminhar ao `127.0.0.1:18080`. Não exponha a porta da aplicação diretamente na internet.
- **Tag de release aprovada** e publicada. O digest da imagem deve ser obtido na página da GHCR; não invente SHA nem utilize `latest`.
- Crie um tenant exclusivo para testes e armazene todos os segredos fora do checkout e do Git.

## Criar os segredos sem exibi-los no terminal

Exemplo de preparação em ambiente autorizado. A senha Redis precisa ser **a senha real do seu Redis externo**; não gere uma senha nova sem configurá-la também no Redis.

```bash
umask 077
mkdir -p "$HOME/limitcore-private"
printf 'staging=%s' "$(openssl rand -hex 32)" > "$HOME/limitcore-private/tenants"
# Salve a senha Redis real, sem quebra de linha, neste arquivo usando seu cofre:
# $HOME/limitcore-private/redis-password
# Não use 'echo senha' nem inclua segredos em comandos compartilhados.
sudo chgrp 10001 "$HOME/limitcore-private/tenants" "$HOME/limitcore-private/redis-password"
chmod 640 "$HOME/limitcore-private/tenants" "$HOME/limitcore-private/redis-password"
```

O usuário que executa o Docker Compose precisa conseguir ler os arquivos; o processo dentro do contêiner roda com UID/GID `10001`. O segredo não aparece na linha de comando ou na configuração Compose, mas será carregado na memória do processo Java. Restrinja também backups e acesso administrativo à máquina.

## Preparar e validar sem iniciar serviços

```bash
git pull --ff-only origin main
cp deploy/vps/.env.example deploy/vps/.env
# Edite deploy/vps/.env com digest real, host/porta Redis, caminhos ABSOLUTOS dos segredos
bash scripts/validate-vps-deploy.sh
```

O preflight falha com placeholders, tag mutável, segredo ausente/fraco, arquivo visível para `others`, porta pública ou Redis local. O arquivo `deploy/vps/.env` está no `.gitignore` e deve ter permissão `chmod 600`.

## Subir, validar e reverter

Use **somente depois** de finalizar os gates operacionais e configurar o reverse proxy HTTPS, DNS, Redis e segredos:

```bash
docker compose -p limitcore --env-file deploy/vps/.env -f deploy/vps/compose.yaml pull
docker compose -p limitcore --env-file deploy/vps/.env -f deploy/vps/compose.yaml up -d --no-build
docker compose -p limitcore --env-file deploy/vps/.env -f deploy/vps/compose.yaml ps
curl --fail --show-error http://127.0.0.1:18080/actuator/health/readiness
```

Depois, valide via URL **HTTPS do staging** com `scripts/staging-smoke.sh`, execute k6, Redis failover, backups e verificação de rollback. Se o Redis estiver indisponível, o readiness deve sair de UP e a API não pode autorizar novas decisões.

Rollback: preserve o digest anterior no sistema de releases, substitua `LIMITCORE_IMAGE` em `deploy/vps/.env` pelo digest anterior verificado, execute o preflight e então `docker compose ... up -d --no-build` (após `pull`). **Rollback de imagem não restaura contadores Redis** nem garante compatibilidade de formatos de chaves. Nunca faça rollback automático antes de examinar os dados e a compatibilidade.

## Limitações e critérios de aprovação

- Um único contêiner na VPS não fornece alta disponibilidade da API. Redis HA separado também requer prova de recuperação, sem prometer zero perda de contadores.
- Sem HTTPS público e política de proxy, os clientes não podem usar essa implantação com segurança.
- A imagem Docker pública só estará disponível depois de criar uma tag aprovada e concluir os workflows `Release` e `Publish OCI Image`; não foi publicado nada automaticamente.
- Contratos e erros: [OpenAPI](../../docs/openapi.yaml). Testes de aceitação: [Go/No-Go](../../docs/release-go-no-go.md).
