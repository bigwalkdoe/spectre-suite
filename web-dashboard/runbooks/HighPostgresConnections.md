# HighPostgresConnections

**Severity:** warning  
**Signal:** PostgreSQL connection usage nearing/exceeding safe threshold (per alert rule).

## Meaning
Connection saturation can cause application errors, timeouts, and degraded query performance.

## Immediate checks
- Prometheus: connection count/max connections, query latency, exporter target health (`postgres` job).
- Database: active/idle connections, long-running queries/locks, and client connection pooling behavior.
- Recent deploys or traffic spikes affecting connection churn.

## Safe mitigations
- Identify and fix connection leaks; ensure clients use pooling and close connections.
- Terminate only clearly stuck/unsafe sessions after impact review.
- Tune pool sizes/timeouts and database `max_connections` as appropriate for resources.

## Verify
- Connection utilization drops below threshold and app errors/timeouts resolve.
- Alert clears and Postgres latency/health stabilize.

## Notes
Coordinate with application owners before terminating sessions in shared environments.
