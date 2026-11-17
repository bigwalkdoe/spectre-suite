# HighCPUUsage

**Severity:** warning  
**Signal:** CPU usage > 80% for 5m (`100 * (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))) > 80`).

## Meaning
Sustained CPU pressure can increase latency, timeouts, and queue/backlog growth.

## Immediate checks
- Prometheus: graph the alert expression and `node_load1` / `node_load5`.
- Identify top consumers: `top`, `htop`, or `ps aux --sort=-%cpu | head`.
- Check for runaway jobs, backups, scans, builds, or container restarts/loops.

## Safe mitigations
- Reduce or reschedule heavy batch jobs (backups/scans/builds) if they overlap.
- Restart only the specific misbehaving service/container after confirming cause.
- Scale resources or tune workload concurrency if pressure is expected.

## Verify
- CPU and load trend down in Prometheus/Grafana.
- Alert clears after the `for` duration and service latency/errors normalize.

## Notes
If correlated with `CriticalCPUUsage` or service-specific alerts, prioritize impacted user-facing paths first.
