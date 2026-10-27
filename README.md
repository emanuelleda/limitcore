# LimitCore

[![CI](https://github.com/emanuelleda/limitcore/actions/workflows/ci.yml/badge.svg)](https://github.com/emanuelleda/limitcore/actions/workflows/ci.yml)
![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)

**Distributed rate-limiting API** written in Java 25, Spring Boot and Redis.

> **Status: early prototype, not production-ready.** Implements a Redis-backed fixed window. Security hardening, integration testing and additional algorithms are outstanding.

## Requirements

- Java 25
- Maven 3.9+
- Docker with Compose

## Quick start

```bash
docker compose up -d
mvn spring-boot:run
```

Check a rate limit:

```bash
curl -sS -X POST http://localhost:8080/v1/limits/check \
  -H 'Content-Type: application/json' \
  -d '{"key":"customer-123","limit":5,"windowSeconds":60}'
```

Example response:

```json
{"allowed":true,"algorithm":"fixed-window"}
```

Once exhausted, the API returns `{"allowed":false,"algorithm":"fixed-window"}` with HTTP 200. The client must inspect the `allowed` field. This is a decision API, not an HTTP middleware returning 429.

## How it works

The API runs a Lua script on Redis to atomically create or increment a counter with expiry. All application instances using the same Redis primary share counters. The window starts on first access, rather than at a calendar boundary.

The key must match `[a-zA-Z0-9:_-]{1,128}`, limit must be 1–1,000,000 and windowSeconds must be 1–86,400.

## Testing

```bash
mvn verify
```

JUnit tests cover allow, deny and null Redis responses using mocks. The GitHub Actions CI workflow executes Maven verification. JaCoCo generates a coverage report. Integration, concurrency and failover tests are not yet implemented. CI success has not been independently verified.

## Security

**Do not deploy publicly.** Clients currently select their own quotas and the API has no authentication or tenant isolation. Redis in Compose binds to loopback for local development. See [SECURITY.md](SECURITY.md).

## Roadmap

- [x] Redis atomic fixed-window prototype
- [x] Docker Compose for local Redis
- [x] Unit tests and CI workflow
- [x] JaCoCo and Dependabot configuration
- [ ] Server-owned policies and API authentication
- [ ] Token bucket and sliding-window algorithms
- [ ] Redis Testcontainers integration and concurrency tests
- [ ] Redis failure modes, backpressure and cardinality protection
- [ ] OpenAPI, metrics, tracing and dashboards
- [ ] SonarQube, SAST and dependency security gates
- [ ] Performance benchmarks and release pipeline

See [architecture](docs/architecture.md), [contributing](CONTRIBUTING.md) and [security policy](SECURITY.md).

## License

MIT — see [LICENSE](LICENSE).
