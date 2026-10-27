# Architecture

Clients -> authenticated HTTP decision endpoint -> Spring Boot -> atomic Redis Lua script.

Multiple instances share state through the same Redis primary. Algorithm selected at startup with LIMITCORE_ALGORITHM.

- Fixed window: counter + TTL.
- Token bucket: fractional refill from Redis server time.
- Sliding window: sorted-set log, unique members via per-key counter, bounded by accepted requests per window.

## Consistency and failure behavior

Lua executes atomically on one Redis primary. Redis replication and failover do not guarantee zero lost increments. No cross-region global consistency guarantee is made. Redis outages produce errors rather than allowing requests. This is not a substitute for API gateway authentication or transport security.

## Operational caveats

The API returns decision JSON, not HTTP 429. The shared API key is a prototype credential, not a tenant identity. Sliding-window storage scales with accepted requests and number of distinct keys. A Redis Cluster deployment needs compatible hash slots for the sorted-set and sequence keys.

See [algorithms](algorithms.md) and [security](../SECURITY.md).
