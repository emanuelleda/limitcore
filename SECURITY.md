# Security policy

This repository is pre-release and not approved for internet-facing production use.

Report vulnerabilities privately through GitHub private vulnerability reporting when available.

## Current safeguards
- Requests require an API key via X-API-Key; an empty server key rejects all requests.
- Quotas are server-owned; request payloads cannot override limits.
- Local Redis Compose port is bound to loopback.
- Redis errors do not automatically grant access.

## Outstanding risks
- One shared API key, no per-tenant authorization, rotation or revocation.
- No network-level request body or key-cardinality controls.
- Redis failover can lose recently acknowledged writes.
- No independent penetration test or load test.
- Metrics and management endpoints require deployment-specific access controls.

Deploy behind a trusted network boundary only. Do not commit credentials.
