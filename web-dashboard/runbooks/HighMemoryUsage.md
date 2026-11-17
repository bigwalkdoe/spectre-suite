# HighMemoryUsage

**Severity:** warning  
**Signal:** Memory usage > 80% for 5m (`100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) > 80`).

## Meaning
Low available memory can lead to swapping, OOM kills, and instability.

## Immediate checks
- Prometheus: memory usage trend, swap usage (`node_memory_Swap*` if available), and load.
- Host/process view: `free -h`, `vmstat 1 5`, `ps aux --sort=-%mem | head`.
- Containers: check for memory growth/leaks and restart counts (cAdvisor/container metrics or `docker stats` when available).

## Safe mitigations
- Restart the specific leaking service/container if identified.
- Reduce workload concurrency/cache sizes where configurable.
- Reclaim disk-backed caches only if appropriate; avoid killing critical system processes.

## Verify
- Available memory recovers and swap/OOM symptoms stop.
- Alert clears and dependent services stabilize.

## Notes
Treat sustained growth as a leak/regression; capture evidence before restarting if possible.
