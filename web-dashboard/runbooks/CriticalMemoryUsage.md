# CriticalMemoryUsage

**Severity:** critical  
**Signal:** Memory usage critically high.

## Meaning
High risk of OOM kills/service crashes.

## Immediate checks
- Same as `HighMemoryUsage`: find top memory consumers, swap/OOM evidence.
- Identify impacted services and data-loss risk.

## Safe mitigations
- Restart or scale the leaking/offending component; reduce load where possible.
- Preserve diagnostics (logs/metrics) before restarts if feasible.

## Verify
- Memory pressure relieved, no ongoing OOMs, alert clears.
