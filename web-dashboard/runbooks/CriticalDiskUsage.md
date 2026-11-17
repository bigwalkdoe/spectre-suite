# CriticalDiskUsage

**Severity:** critical  
**Signal:** Root filesystem usage critically high.

## Meaning
Imminent risk of write failures affecting apps, DBs, backups, and monitoring.

## Immediate checks
- `df -h`, largest directories/files, Docker/log growth, backup repo usage.
- Confirm whether monitoring metrics are available (node filesystem series coverage).

## Safe mitigations
- Free space immediately via safe cleanup per policy (logs/temp/known artifacts).
- Pause non-essential write-heavy jobs until stable.

## Verify
- Free space restored above critical threshold; alert clears.
