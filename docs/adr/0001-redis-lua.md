# ADR-0001: Redis Lua for atomic quota decisions

Status: Accepted for prototype

## Context
Multiple stateless API instances must share rate-limit state without application-level locks.

## Decision
Use Redis Lua scripts, with Redis server time for sliding-window and token-bucket. Co-locate multi-key script keys in the same Redis Cluster hash slot using braces.

## Consequences
Atomicity applies on one Redis primary, not across independent regions. Redis failover may lose acknowledged writes. Sliding-window logs use O(capacity) entries per active key; operational bounds and cardinality protections remain future work. This design requires load and failover testing before production adoption.
