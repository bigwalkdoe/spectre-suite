# CriticalCPUUsage

**Severity:** critical  
**Signal:** CPU usage critically high for sustained period.

## Meaning
Severe CPU saturation likely impacting availability/latency.

## Immediate checks
- Same triage as `HighCPUUsage` with urgency: identify dominant processes/containers and user impact.
- Check for runaway loops, fork storms, or stuck batch jobs.

## Safe mitigations
- Throttle/stop offending non-critical workload; restart specific failing service if safe.
- Escalate for capacity scaling if legitimate load.

## Verify
- CPU/load and service health recover; alert clears.
