# BlackboxExporterDown

**Severity:** critical  
**Signal:** `up{job="blackbox-http"}` (or blackbox scrape target) indicates exporter is down.

## Meaning
Synthetic uptime/latency/TCP/ICMP probe results may be unavailable; endpoint failures can go undetected.

## Immediate checks
- Prometheus Targets: blackbox-related jobs and `up` values.
- Service status/logs: `docker compose -f docker-compose.monitoring.yml ps blackbox-exporter` and container logs.
- Network reachability from exporter to configured probe targets.

## Safe mitigations
- Restart `blackbox-exporter` if unhealthy.
- Validate `prometheus/blackbox-exporter.yml` and probe module configuration after changes.
- Confirm DNS/network dependencies for external probes.

## Verify
- Blackbox targets up and `probe_success`/latency metrics resume.
- Uptime-related alerts reflect real endpoint state.

## Notes
While down, absence of probe failures does not imply endpoints are healthy.
