# Operations and incident response

## Local monitoring

Start the API on the host, then run Prometheus from the optional monitoring Compose file. The metrics endpoint is /actuator/prometheus. **Do not expose management endpoints to untrusted networks**; Spring Boot recommends securing them or keeping them behind a firewall.

## Redis outage

LimitCore currently fails closed in the sense that it does not grant a positive decision when Redis is unreachable. The endpoint responds with a server error; callers must treat such errors as a denied/unknown decision and choose their own safe handling.

## Failover

Lua is atomic on one primary but Redis replication may lose recent writes during failover. Test failover behavior in your own environment before relying on strict limits.

## Security

Set LIMITCORE_API_KEY from a secret manager, use HTTPS at an ingress, restrict access to Redis and the management endpoints, and rotate keys during a maintenance window. The prototype uses one global API key and does not yet support rotation without downtime.

## Runbooks

- If 5xx spikes: check Redis connectivity, health and logs; do not bypass limits blindly.
- If 401 spikes: check client key distribution and key rotation.
- If Redis memory increases: inspect active-key cardinality and sliding-window storage.
- If response latency increases: measure Redis RTT and check for CPU saturation.

## Release checklist

CI green; security workflow green; dependency audit reviewed; load test performed; failover exercise documented; credentials managed; metrics access restricted; rollback plan rehearsed.
