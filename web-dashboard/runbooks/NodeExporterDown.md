# NodeExporterDown

**Severity:** critical  
**Signal:** `up{job="node"}` indicates node-exporter target is down/unreachable.

## Meaning
Host-level metrics (CPU, memory, disk, network, load) may be stale or unavailable, degrading visibility and disk-based alerts.

## Immediate checks
- Prometheus Targets/Graph: confirm `up{job="node"}`.
- Container/service: `docker compose -f docker-compose.monitoring.yml ps node-exporter` and logs.
- Endpoint reachability from Prometheus network: scrape URL/port `node-exporter:9100`.

## Safe mitigations
- Restart `node-exporter` service if crashed/misconfigured.
- Verify mounts/permissions; on hosts with Docker user namespaces, `pid: host` is incompatible and filesystem metrics may be limited (see compose comments).
- Check recent config/deploy changes affecting monitoring network or container health.

## Verify
- `up{job="node"} == 1` and node metrics resume updating.
- Dashboard diagnostics show node exporter healthy.

## Notes
While down, treat absence of host alerts/metrics as unknown, not healthy.
