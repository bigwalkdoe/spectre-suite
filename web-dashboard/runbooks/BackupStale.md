# BackupStale

**Severity:** warning/critical (per rule)  
**Signal:** Backup freshness metric indicates last successful backup is older than expected.

## Meaning
Recent backups may not be completing; recovery point objective (RPO) may be at risk.

## Immediate checks
- Dashboard Backup Status and Diagnostics (backup/restic exporters).
- Prometheus: `backup_last_success_timestamp`, `restic_last_success_timestamp`, related health/verify metrics and alert details.
- Host handler/logs for backup jobs and `spectre` backup actions; check disk space and repo availability.

## Safe mitigations
- Resolve blocking issues first (disk full, repo unreachable, auth/credentials, locked repo).
- Trigger an allowlisted backup action from the dashboard/host handler once prerequisites are healthy.
- Avoid destructive repo operations without verified backups.

## Verify
- New successful backup timestamp recorded and backup health metrics recover.
- Alert clears and offsite/verify checks (if applicable) are healthy.

## Notes
If backups repeatedly fail or repo integrity is suspect, escalate before making retention/prune changes.
