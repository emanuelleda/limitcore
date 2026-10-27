# Rate-limiting algorithms

All limits are server-configured via environment variables. Every request must supply an X-API-Key matching LIMITCORE_API_KEY.

- **fixed-window**: Redis atomic Lua increment, expiry starts at the first accepted request. Can permit bursts at window boundaries.
- **token-bucket**: Redis TIME-based refill, capacity = LIMITCORE_CAPACITY and refill rate = capacity / window seconds. Supports bursts up to capacity.
- **sliding-window**: Redis sorted-set log of accepted events, prunes expired members and uses a per-key sequence for unique entries. Memory usage is O(capacity) per active key.

Configuration:
```bash
export LIMITCORE_API_KEY='replace-with-a-long-random-secret'
export LIMITCORE_ALGORITHM=token-bucket
export LIMITCORE_CAPACITY=100
export LIMITCORE_WINDOW_SECONDS=60
```

Limitations: single shared API key; no multi-tenant policy registry; 200 response with allowed boolean; Redis primary failover can lose writes; cross-region global limits not supported. Redis errors fail closed through HTTP 5xx, rather than granting requests. Protect API and Redis at the network boundary.
