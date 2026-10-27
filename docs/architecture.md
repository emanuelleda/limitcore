# Architecture and guarantees

Client -> Spring Boot REST -> Redis Lua script.

The script executes atomically on a single Redis primary. It increments a per-key counter and sets expiry on first access. This is a fixed-duration window anchored to first request, not a calendar-aligned window. Requests after the limit return allowed=false with HTTP 200.

## Limitations

- Redis failover can lose acknowledged writes depending on replication and persistence.
- A client currently chooses its quota; the service is not safe for untrusted callers.
- No tenant-level authorization or key cardinality limit.
- No availability guarantees during Redis outages.
- A Lua operation is atomic on one Redis server, not globally across independent regions.

## Production milestones

Implement server-managed policies, auth, token bucket and sliding window, Testcontainers-based concurrency tests, metrics, tracing, resource bounds, resilience and load testing before claiming production readiness.
