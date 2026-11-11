# Automation Hardening for Self-Maintenance (Backups + Security Posture)

**Date:** 2026-11-11  
**Status:** Proposed (pending approval)  
**Approach:** A — Safe scheduled hardening

## Intent & why

Harden Spectre Suite automation so routine maintenance happens without operator intervention: backup storage is reclaimed automatically before it becomes a space problem, and security posture is checked frequently with guarded, safe/idempotent remediation to reduce drift and stale signals.

## Goals

1. **Backups trim automatically to create space**
   - Ensure restic repositories are regularly pruned/forgotten in a tag-scoped way so unreferenced data is reclaimed.
   - Add conservative, configurable trimming of local backup artifacts/dumps to prevent accumulation in backup/state directories.
   - Preserve backup correctness and safety (never unscoped forget, no deletion of current/valid in-retention backups, dry-run/visibility where practical).

2. **Security posture scans every 15 minutes with possible self-remediation**
   - Run a lightweight security posture maintenance cycle every 15 minutes (scheduled automation).
   - Refresh/export posture signals and record health/status markers/logs for observability.
   - Perform **only clearly safe, idempotent self-remediation** by default (guardrailed; no destructive or risky changes).

## Non-goals

- Replacing the existing restic backup/verify engines or changing snapshot contents/targets semantics except where required for retention/pruning configuration.
- Full autonomous incident response, aggressive auto-healing, or remediation actions that can disrupt workloads/services without explicit opt-in.
- Guaranteeing remediation of every security finding; this design focuses on frequent posture checks, visibility, and safe maintenance fixes.
- Offsite/provider-specific behavior beyond existing restic/rclone configuration.

## Anti-goals

- Any unscoped `restic forget`/prune or deletion outside configured/tag-scoped/retention-bounded paths.
- Automatic remediation that modifies firewall/network policy, restarts arbitrary services/containers, applies package upgrades, rewrites security configs broadly, or deletes backups that may still be required within retention.
- Hardcoding secrets, host-specific absolute paths in ways that break repo portability, or making timers depend on interactive/GUI sessions.

## Constraints

- Follow existing repo patterns: canonical actions under `spectre/actions/`, dispatch via `spectre run`/registry where appropriate, systemd units/timers in `systemd/` and/or installer actions consistent with current restic/baseline timer installers.
- Restic operations must remain **tag-scoped** (`--tag ${RESTIC_TAG:-spectre-suite}`) and preserve repository/password/config safety.
- Self-remediation must be **safe and idempotent by default** (create missing dirs, fix safe permissions/ownership where appropriate and non-destructive, remove only known-stale temp/marker-age artifacts per policy, refresh metrics/status) with logging and non-zero/marker signaling on failure.
- Schedules must be explicit and automation-friendly (`Persistent=true` where appropriate); 15-minute posture cadence as requested.
- Do not break existing timers/services/contracts (e.g. backup/verify/catchup, baseline metrics exporters, alerting markers) unless intentionally and safely superseded.

## Approaches considered

- **A) Safe scheduled hardening (selected):** automated tag-scoped restic/local trimming + 15-minute posture scan with safe-only self-remediation and guardrails.
- **B) Visibility-first:** automated trimming, but 15-minute scans only report/export/alert with no remediation.
- **C) Aggressive self-healing:** tighter/broader cleanup and stronger auto-remediation, higher risk of unintended side effects.

**Selected:** A. **Self-remediation scope (default, my call):** limited to clearly safe, idempotent fixes (no risky/destructive actions). Specific additional remediations can be added later behind explicit flags/config.

## Design

### 1) Backup trimming and space reclamation

#### 1.1 Restic prune scheduling (space reclamation)
- Add a dedicated, repo-managed restic prune automation path:
  - **Action:** reuse/register `spectre/actions/backups/restic/prune.sh` (`spectre run backups/restic/prune`) as the canonical prune entrypoint (already tag-scoped, supports `--dry-run` and `--repo` selection).
  - **Timer/service:** provide `systemd/spectre-restic-prune.timer` and `systemd/spectre-restic-prune.service` (or an installer action following `install-restic-timer.sh`/`install-restic-verify-timer.sh` patterns) to run prune on a regular schedule (default: **daily**, after backup/verify windows, with `Persistent=true` and jitter). Schedule should be configurable in unit/env/install args where the pattern allows.
  - Prune remains **tag-scoped** via existing `restic_forget_args` and must target configured local/offsite repos per existing behavior/config.

#### 1.2 Configurable retention (backward-compatible)
- Make retention policy configurable while preserving current defaults in `spectre/actions/backups/restic/common.sh`:
  - `RESTIC_KEEP_HOURLY` (default 24), `RESTIC_KEEP_DAILY` (default 30), `RESTIC_KEEP_WEEKLY` (default 12), `RESTIC_KEEP_MONTHLY` (default 12), `RESTIC_KEEP_LAST` (default 1).
  - `restic_forget_args` builds `forget` args from these values.
- Document relevant env knobs in `config/backups/restic/env.example` as applicable (including how they relate to pruning/reclamation) without breaking existing deployments.

#### 1.3 Local backup artifact trimming (conservative)
- Add `spectre/actions/backups/trim-backup-artifacts.sh` (and register in dispatch/registry as appropriate) to free space in local backup storage safely:
  - **Scope:** configured backup artifact/state directories (defaults aligned with existing usage, e.g. `/backups/databases`, `/backups/docker-volumes`, and restic state/dumps under suite state dirs) — only known paths/patterns.
  - **Behavior:**
    - Support `--dry-run`, configurable retention (e.g. days) and path overrides via env/flags.
    - Remove **hollow/unusable** archives using the same structural validation principles as `check-backup-health.sh` (never size-only deletion that could remove valid small backups).
    - Prune **old valid artifacts** beyond retention (e.g. age-based for timestamped archive patterns owned by Spectre backups) to create space; keep most-recent/safety minimums where sensible.
    - Clean stale temporary/dump directories older than a safe threshold in suite backup state dirs.
  - **Safety/logging:** print/report what is kept/removed (or would be removed), exit non-zero on operational errors, and never touch restic repository internals except via restic commands.
- Add a systemd timer/service (daily, `Persistent=true`, after backup/prune windows or at a low-impact time) to run the trim action automatically.

#### 1.4 Observability
- Trimming/prune actions log outcomes and integrate with existing marker/health conventions where feasible (without breaking current marker semantics).
- Failures should be visible (non-zero exit, logs/journal) so alerting/runbooks can detect when self-maintenance cannot reclaim space.

### 2) Security posture scan every 15 minutes with safe self-remediation

#### 2.1 Posture maintenance action
- Add a canonical action, e.g. `spectre/actions/security/security-posture-maintenance.sh` (name finalized in implementation; registered in dispatch), invoked as `spectre run security/security-posture-maintenance`.
- **Cadence:** every 15 minutes via systemd timer/service (repo-managed unit files and/or installer consistent with existing patterns). `Persistent=true`, with small randomized delay/jitter to avoid thundering herd.
- **Scan/check cycle (lightweight, posture-focused):**
  - Refresh security posture/baseline exports and signals where available (e.g. run `prometheus/security-baseline-metrics-exporter` and/or `prometheus/security-metrics-exporter` if present/healthy to invoke) so metrics stay current.
  - Run quick, read-mostly posture checks already supported by the repo where safe/fast (e.g. config/dispatch consistency checks, security scan outcome/baseline freshness checks, or targeted status checks) and summarize results.
  - Write a concise status summary/markers (timestamp, overall status, checks run, remediations applied/skipped) to a state/log location for observability.

#### 2.2 Safe/idempotent self-remediation (default)
- When remediation is enabled (default for the scheduled maintenance path, and/or via `--remediate` flag — finalized in implementation), apply **only** clearly safe, idempotent fixes such as:
  - Ensure required state/log/metrics directories exist with safe permissions.
  - Remove stale, known-temporary scan/export artifacts older than a threshold (not scan results needed for audit/history within retention).
  - Re-run/re-generate local textfile metrics/exports to correct staleness caused by missed runs (idempotent).
  - Normalize/refresh internal status markers produced by this maintenance action.
- **Explicitly excluded unless later opted-in:** restarting services/containers, changing firewall/SELinux/AppArmor/network settings, modifying application/security policy configs, installing/removing packages, killing processes, or deleting user/data backups.
- All remediation attempts are logged with what changed or was skipped; failures do not mask scan results.

#### 2.3 Guardrails & observability
- Support `--dry-run` and/or `--check-only` mode for validation.
- Bounded runtime/clear logging (suitable for a 15-minute timer); avoid heavy network/package scans in the 15-minute loop (those remain in existing scheduled scans like weekly security hardening / image/dependency scans).
- Non-zero exit on scan/remediation failures so systemd/monitoring can surface issues.

### 3) Documentation and registry
- Register new actions/timers in `spectre/dispatch/registry_data.json` and add/update systemd unit files/installers as needed.
- Update relevant docs/runbooks (backup retention/pruning, security posture automation) to reflect automated trimming and 15-minute posture maintenance, including safe-remediation boundaries and how to disable/dry-run.

## Assumptions (my call, unless you object)

- **Local backup retention default:** conservative age-based trimming for Spectre-owned timestamped artifacts (exact default days chosen in implementation, e.g. 14–30 days) with `--dry-run` and config overrides; hollow/unusable artifacts eligible for removal when structurally invalid.
- **Restic prune cadence:** daily scheduled prune is acceptable (in addition to any prune performed during backup) to ensure timely space reclamation.
- **15-minute posture scan content:** lightweight and local/fast (metrics refresh + quick checks/status) rather than full dependency/container/image/network hardening scans; heavy scans keep their existing schedules.
- **Remediation boundary:** safe/idempotent fixes only, as listed above; no service restarts or config mutations by default.

## What’s left to the builder

- Final names/paths for new action(s), unit files, and installer scripts consistent with repo conventions.
- Exact default schedules/times, retention day values, directory allowlists/patterns, and which quick checks are included in the 15-minute posture cycle (based on available actions and runtime cost).
- Precise marker/log file names and registry metadata (group, sudo, mutates, schedule hints) aligned with existing entries.
- Any minimal refactors needed to make retention configurable without changing default behavior.
- Verification steps (dry-runs, `spectre actions verify`/dispatch checks as applicable, `systemd-analyze verify` if used in repo, and safe local validation of scripts).

## Approval

Implementation must not begin until this design is approved. After approval, the next step is to invoke `superpowers:writing-plans` and create an implementation plan.
