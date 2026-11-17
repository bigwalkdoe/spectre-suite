# Watchdog

**Severity:** none (dead-man's switch)  
**Signal:** `vector(1)` alert intended to be always firing.

## Meaning
This alert exists to verify the end-to-end alerting/notification pipeline. **If you receive/see Watchdog as expected, notification delivery is working.** The real problem is when Watchdog is missing/stale because it can indicate Alertmanager/notification/routing issues.

## Immediate checks
- Prometheus Alerts: Watchdog should be firing continuously.
- Alertmanager: route/receiver for `alertname="Watchdog"` and recent notifications.
- Prometheus/Alertmanager health and connectivity (`up` targets, logs).

## Safe mitigations
- Investigate Alertmanager config, secrets, receiver auth, and network egress if notifications stop.
- Reload/restart Alertmanager/Prometheus only after confirming config validity.

## Verify
- Watchdog remains firing in Prometheus and is delivered via the configured watchdog/heartbeat channel as designed.

## Notes
Do not silence or "fix" by disabling Watchdog without replacing the heartbeat coverage.
