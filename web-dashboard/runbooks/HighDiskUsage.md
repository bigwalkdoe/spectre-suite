# HighDiskUsage

**Severity:** warning  
**Signal:** Root filesystem usage > 80% for 5m (`node_filesystem_*{mountpoint="/"}`).

## Meaning
Low disk space can break logging, backups, databases, container image pulls, and updates.

## Immediate checks
- Prometheus: disk usage trend and related `BackupRepoFreeSpaceLow`/`BackupRepoWillFillIn7Days` alerts.
- Host: `df -h /`, `du -xhd1 / | sort -h`, check `/var/lib/docker`, logs, backups, and temp files.
- Confirm metrics source health: if `node_filesystem_*` is missing, check node-exporter coverage (including userns/`pid:host` constraints).

## Safe mitigations
- Remove old logs/artifacts/temp files you know are safe; rotate/compress logs.
- Prune unused Docker artifacts cautiously (`docker system df`, targeted prune).
- Free backup/repo space according to retention policy; do not delete active backups blindly.

## Verify
- `df -h /` and Prometheus show recovered free space.
- Alert clears and backup/write operations succeed.

## Notes
Escalate quickly if usage is rising fast or on critical data volumes.
