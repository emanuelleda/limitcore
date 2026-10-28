# Referência Kubernetes — NÃO implantar sem configuração

O arquivo `limitcore.example.yaml` é uma **referência**, não um ambiente de produção provisionado. Ele demonstra segurança por padrão, três réplicas, readiness/liveness, rollout gradual, PDB e HPA. **Nenhuma imagem ou senha real é criada por este manifesto.**

## Pré-requisitos obrigatórios

1. Cluster com disponibilidade e métricas de CPU (HPA via Metrics Server) e controle de rede.
2. Redis gerenciado ou Sentinel/Cluster operado separadamente com TLS, autenticação, backups, monitoramento, políticas de memória e failover testado.
3. Imagem GHCR versionada construída e verificada pelo workflow **Publish OCI Image**. Substitua `REPLACE_WITH_PUBLISHED_IMAGE_DIGEST` pelo **digest sha256 real**; não publique nem use a tag `latest`.
4. Configure `REPLACE_WITH_TLS_REDIS_HOST` para o endereço TLS do Redis. Confirme compatibilidade de certificados com a JVM.
5. Provisione `Secret/limitcore-secrets` com campos `tenants` e `redis-password` por um gerenciador de segredos externo. **Nunca faça commit desses valores.** Distribua chaves de pelo menos 32 caracteres por tenant e desative o modo legado em implantação multitenant.
6. Configure ingress HTTPS, rate limiting e proteção por origem/IP na borda; rede restrita ao Redis; ServiceAccount mínimo; NetworkPolicy conforme o seu plugin CNI.
7. Defina orçamento de recursos, SLO, alertas e plano de rollback para a sua infraestrutura.

## Verificação e implantação

Em uma máquina com acesso autorizado ao cluster:

```bash
kubectl apply --dry-run=server -f deploy/k8s/limitcore.example.yaml
kubectl apply -f deploy/k8s/limitcore.example.yaml
kubectl rollout status deployment/limitcore --timeout=5m
kubectl get pods -l app=limitcore
```

Antes dos comandos, substitua os placeholders e crie o Secret de forma segura. Faça primeiro em *staging*; não aplique esta referência diretamente em produção. Os probes acessam `/actuator/health/liveness` e `/actuator/health/readiness`: **readiness deve cair quando Redis não está saudável sem reiniciar a JVM em loop**.

## Rollback

```bash
kubectl rollout history deployment/limitcore
kubectl rollout undo deployment/limitcore
kubectl rollout status deployment/limitcore --timeout=5m
```

Rollback do contêiner **não** restaura contadores Redis; mudanças de formato de chaves e de algoritmos exigem plano de migração próprio. Não faça rollout simultâneo entre versões que usam namespaces Redis incompatíveis sem plano de transição.

## Observações

- `SPRING_PROFILES_ACTIVE=production` obriga TLS Redis e pelo menos uma credencial por tenant/legada; a configuração da aplicação rejeita uma inicialização insegura.
- A imagem executa com UID 10001, sistema de arquivos somente leitura e volume temporário limitado.
- O HPA dimensiona a API, **não** o Redis. Os contadores de um tenant compartilham o mesmo *hash slot*; avalie chaves quentes e memória do Redis sob carga.
- A publicação real do GHCR, a restrição de acesso ao pacote, os segredos, DNS, ingress, certificados e políticas de rede dependem do ambiente e precisam de validação humana.
