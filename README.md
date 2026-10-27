# LimitCore

[![CI](https://github.com/emanuelleda/limitcore/actions/workflows/ci.yml/badge.svg)](https://github.com/emanuelleda/limitcore/actions/workflows/ci.yml)
![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)

Distributed rate-limiting decision API built with Java 25, Spring Boot and Redis.

> **Pre-release.** Not yet security-audited or validated for production. New CI runs must pass before the latest changes are considered verified.

## Requirements

Java 25, Maven 3.9+, Docker Compose.

## Quick start

```bash
docker compose up -d
export LIMITCORE_API_KEY="$(openssl rand -hex 32)"
export LIMITCORE_ALGORITHM=token-bucket # fixed-window | token-bucket | sliding-window
export LIMITCORE_CAPACITY=100
export LIMITCORE_WINDOW_SECONDS=60
mvn spring-boot:run
```

```bash
curl -X POST http://localhost:8080/v1/limits/check \
  -H "X-API-Key: $LIMITCORE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"key":"customer-123"}'
```

Response: `{"allowed":true,"algorithm":"token-bucket"}`. Denied decisions return `allowed:false` with HTTP 200; consumers must inspect the response. Invalid/missing API keys return HTTP 401.

## Configuration

| Environment variable | Default | Purpose |
| --- | --- | --- |
| LIMITCORE_API_KEY | empty (reject all) | Shared API credential |
| LIMITCORE_ALGORITHM | fixed-window | Algorithm |
| LIMITCORE_CAPACITY | 100 | Requests/tokens |
| LIMITCORE_WINDOW_SECONDS | 60 | Window/refill period |
| REDIS_HOST | localhost | Redis hostname |
| REDIS_PORT | 6379 | Redis port |

## Tests and quality

Run `mvn verify` for JUnit tests and JaCoCo report. GitHub Actions runs the Maven verification pipeline; Dependabot checks dependencies weekly. Testcontainers dependencies are included, but Redis integration and concurrency tests are **not yet implemented**. SonarQube and tracing are also pending.

## Architecture

See [algorithms](docs/algorithms.md), [architecture](docs/architecture.md), [security](SECURITY.md), [contributing](CONTRIBUTING.md).

## Roadmap

- [x] Atomic Redis-backed fixed-window, token-bucket and sliding-window decisions
- [x] Shared API key and server-owned quotas
- [x] JUnit mock tests, CI, JaCoCo, Dependabot
- [x] Docker Compose, container image and Prometheus registry dependency
- [ ] Integration and concurrency tests against real Redis
- [ ] Tenant-aware authentication, policies and quotas
- [ ] OpenAPI specification, dashboards and distributed tracing
- [ ] SAST, SonarQube, release automation and benchmarks
- [ ] Failover testing, bounded memory and operational readiness review

Licensed under MIT.
