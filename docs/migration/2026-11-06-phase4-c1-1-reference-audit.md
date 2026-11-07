# Phase 4 / C1.1 — Reference Audit (NO DELETIONS)

**Status:** Audit complete (repo-side). **No `git rm`, no file deletions, no host changes performed.**  
**Date:** 2026-11-06  
**Branch/context:** `main` @ `6248692` (post-merge of consolidation Phase 1 shims/Phase 2-3 repointing).  
**Preconditions checked:** `spectre actions verify` (host inventory) → **0 findings**. Schedulers on the reference host dispatch via `/usr/local/bin/spectre run <job>` (per prior runbook).  
**Parent plan:** `docs/migration/2026-11-06-phase4-c1-repo-inventory-plan.md`

## Scope
Searched for references to legacy repo paths:
- `\bscripts/` across `*.sh,*.py,*.yml,*.yaml,*.md,*.service,*.timer,Dockerfile*,Makefile*` (375 hits total; many in `docs/` historical/superpowers material).
- `prometheus/(business-metrics-exporter|security-metrics-exporter)\.sh` across the repo (runtime/config/test hits outside migration/superpowers docs are the key set).
- Reviewed `.github/workflows/*`, `install.sh`, repo `systemd/`, `docker-compose.monitoring.yml`, `spectre/` (Python/actions), and key runtime scripts.

Legacy trees in repo: `scripts/` contains 74 `.sh` files mirroring `spectre/actions/` (spot checks confirm Phase 1 forwarders delegating to canonical actions; byte-different from canonical). `prometheus/business-metrics-exporter.sh` and `prometheus/security-metrics-exporter.sh` are 7-line forwarders to `spectre/actions/prometheus/*-exporter.sh`.

## Classification

### A — MUST REWIRE before removing legacy paths (runtime / CI / install / test correctness)
These will break functionality, CI, or tests if `scripts/` or top-level `prometheus/*-exporter.sh` are removed without rewiring.

| Area | Files / evidence | Issue | Rewire direction |
|---|---|---|---|
| Canonical dashboard trigger executor | `spectre/actions/dashboard-actions/process-triggers.sh:22-24,50-58` | **Runtime:** allowlist maps actions to `scripts/backups/run-missed-backups.sh`, `scripts/maintenance/run-maintenance.sh`, `scripts/security/scan-docker-images.sh` and executes `$REPO_ROOT/$script_rel`. Removing `scripts/` breaks dashboard-triggered actions. `systemd/dashboard-actions/spectre-dashboard-actions.service` invokes this canonical action (good), but the action itself targets legacy paths. | Dispatch via `spectre run <job>` (jobs exist: `backups/run-missed-backups`, `security/scan-docker-images`; confirm `maintenance/run-maintenance` registry mapping before changing) or execute canonical `spectre/actions/...` paths. Keep allowlist semantics/security checks. |
| User-timer installers (canonical actions) | `spectre/actions/systemd/install-restic-timer.sh`, `install-restic-verify-timer.sh`, `install-backup-catchup-timer.sh` | **Generated host units exec repo `scripts/...` paths** (e.g. `ExecStart=$PROJECT_ROOT/scripts/backups/restic/backup.sh`, `$PROJECT_ROOT/scripts/backups/run-missed-backups.sh`). Existing installed user units on migrated hosts may already point to `spectre run` (runbook shows repointed); *new* installs from these scripts would recreate legacy-path coupling. `tests/test_restic_timer_installers.sh` asserts `scripts/...`. | Prefer generating units that `ExecStart=/usr/local/bin/spectre run <job>` (or configurable spectre path) consistent with consolidation; update tests accordingly. Alternatively target `spectre/actions/...` if `spectre` may be absent, but document divergence from §8.2/dispatch model. |
| Installer | `install.sh` (many refs) | **Major legacy behavior:** copies `scripts/*/*.sh` to `/usr/local/bin`, generates systemd units calling `/usr/local/bin/*.sh`, hardening helpers invoked by name from `/usr/local/bin`. Contradicts consolidation §8.2 and README warning; breaks if `scripts/` removed. | Rewrite to install `spectre` CLI only + units that `spectre run <job>` (per spec/README). Treat as dedicated migration task; do not block C1 audit, but C1 deletion of `scripts/` makes `install.sh` nonfunctional. |
| CI workflows | `.github/workflows/lint.yml:166,173,196,203,215,216`; `security-scanning.yml:83,84,99,129`; `disaster-recovery-test.yml:19-23`; `test-suite.yml`/`ml-anomaly-test.yml` (ML paths under `scripts/ml-anomaly/*` - **see B/C note**) | CI invokes legacy `scripts/check-config-consistency.sh`, `scripts/check-docs-references.sh`, OPA paths under `scripts/security/opa/*`, backup script existence checks, ML pipeline under `scripts/ml-anomaly/*`. Lint/OPA/doc checks have canonical equivalents in `spectre/actions/*` and/or `spectre/policies/*`? (verify OPA location). | Rewire to canonical paths (`spectre/actions/check-config-consistency.sh`, `.../check-docs-references.sh`, canonical OPA/policy/baseline locations) and/or `spectre`/pytest entrypoints. `scripts/ml-anomaly` contains Python assets (not just forwarders) — **do not treat as forwarder-only**; confirm canonical location before rewiring/removal. |
| Test harness & tests | `tests/run_tests.sh` (shellcheck/syntax/dir walks over `scripts/**/*.sh`, `scripts/*/*.sh`; expects `scripts/*` dirs), plus many tests: `test_backup*.sh`, `test_backup_catchup.sh`, `test_restore.sh`, `test_security.sh`, `test_schedule_ownership.sh`, `test_restic_*.sh`, `test_ml.sh`, `test_config_consistency.sh` (copies from `spectre/actions` into temp `scripts/` — intentional), `test_security_metrics.sh`/`test_restic_exporter.sh` (prometheus top-level exporters) | Large coupling: tests validate/lint/execute legacy paths or assume `scripts/` layout. Some tests intentionally exercise forwarders/legacy behavior; others target canonical behavior via legacy path. | Define strategy: (1) move lint/syntax/coverage to `spectre/actions/**/*.sh` (+ keep explicit forwarder tests if compatibility retained), (2) update tests to invoke canonical actions or `spectre run` where appropriate, (3) update `test_restic_exporter.sh`/`test_security_metrics.sh`/config-consistency references to canonical `spectre/monitoring/exporters/*` or registry action paths once Tier A resolved, (4) rebaseline `tests/run_tests.sh` counts/expectations. Batched, with green tests each step. |
| Exporter references (Tier A) | `tests/test_restic_exporter.sh:7`, `tests/test_security_metrics.sh:18`, `spectre/actions/check-config-consistency.sh:22` reference `prometheus/*-exporter.sh`; `spectre/dispatch/registry_data.json` has `"action": "prometheus/business-metrics-exporter.sh"` / `security-metrics-exporter.sh`; `prometheus/alert_rules.yml` contains text mentioning exporter script names; `prometheus/business-metrics/README.md`. | Top-level `prometheus/*-exporter.sh` are forwarders, but registry/action resolution and config-consistency/tests currently point at them. Removing before rewiring can break verify/tests/config checks depending on how actions resolve. | Audit dispatch resolver/registry semantics for these action paths; rewire tests and `check-config-consistency` to canonical exporter path or stable `spectre run`/action resolution; keep alert rule *descriptions* accurate (text-only). Treat Tier A as small but not zero-risk. |
| Repo systemd templates | `systemd/ml-anomaly-fix.service` → `/opt/spectre-suite/scripts/ml-anomaly/*`; `systemd/dashboard-actions/spectre-dashboard-actions.service` → `%h/.../scripts/dashboard-actions/process-triggers.sh` (repo legacy path) though canonical action exists under `spectre/actions/dashboard-actions/process-triggers.sh`; `examples/systemd-timers-example/custom-backup.service`. | Templates/examples point at legacy/non-canonical paths; may mislead operators or break if copied. | Update to canonical paths / `spectre run`. `ml-anomaly` layout needs canonical confirmation (contains Python code/data). |

### B — SHOULD UPDATE (operator-facing docs/messages; not runtime/CI-blocking if understood)
| Area | Evidence | Action |
|---|---|---|
| README | Multiple `scripts/...` command examples (`install-backup-catchup-timer.sh`, `setup-notification-channels.sh`, restic prune/restore/timer installers), structure listing, legacy notes. | Update operator examples to canonical `spectre run` / `spectre/actions/...` / installed `spectre` workflow where stable; keep explicit legacy/compat notes only if paths retained. |
| Stale message | `spectre/actions/setup-notification-channels.sh:67` says “Expected the script to live in <repo>/scripts/”. | Update message to reflect canonical location. |
| docker-compose comments | `docker-compose.monitoring.yml:101,317` reference `scripts/setup-notification-channels.sh` and `scripts/dashboard-actions/process-triggers.sh`. | Update comments to canonical paths/`spectre` commands. |
| CHANGELOG / alertmanager/prometheus prose comments | Historical/operational text references `scripts/...` and exporter script names. | Update where it improves current operator accuracy; preserve historical meaning when appropriate. |
| Canonical exporter comments | `spectre/monitoring/exporters/business-metrics-exporter.sh` comments mention marker writers under `scripts/...`. | Optional/comment-only; safe. |

### C — HISTORICAL / CONTEXTUAL (keep meaning; usually no rewiring required for C1 mechanics)
| Area | Evidence | Action |
|---|---|---|
| Migration/superpowers docs | `docs/migration/*.md`, `docs/superpowers/specs/*.md`, `docs/superpowers/plans/*` contain extensive legacy-path references as inventory/history/design context. | **Preserve historical accuracy.** Do not mass-edit. Add notes only if needed to avoid operator confusion. |
| `spectre/dispatch/verify.py` | Docstring/example text includes `scripts/t/beta.sh`. | Harmless example; optional. |
| `tests/test_config_consistency.sh` temp sandbox | Creates temp `scripts/` dir to exercise path logic; copies canonical checker. | Intentional test fixture, not legacy dependency. |
| `tests/test_schedule_ownership.sh` | Checks `/home/deon/scripts/` absence and mentions `scripts/` consolidation — host/fork context differs from repo `scripts/` tree. | Review carefully; fork-root check is not the same as repo legacy forwarders. |

## Key findings / corrections to parent plan
1. **Forwarder classification heuristic was misleading but substance confirmed:** repo `scripts/**/*.sh` are effectively Phase 1 forwarders/delegators (spot checks), not duplicate full implementations. C1.2 must still confirm per path before bulk removal.
2. **`scripts/` is not forwarder-only in effect:** `scripts/ml-anomaly/` contains Python/ML assets referenced by README, CI, tests, and systemd template (`run_ml_pipeline.sh`, requirements, venv expectations). Treat ML paths separately from shell forwarders.
3. **Canonical code still targets legacy paths:** `spectre/actions/dashboard-actions/process-triggers.sh` executes `scripts/...` allowlisted scripts — this is the highest-priority runtime rewiring issue found.
4. **Timer installers + tests encode legacy exec paths:** `spectre/actions/systemd/install-*-*.sh` and `tests/test_restic_timer_installers.sh`/catchup tests create/assert `scripts/...` execution.
5. **Tier A (`prometheus/*-exporter.sh`) is coupled to registry/tests/config checks, not just files on disk.**

## Recommended next confirmed steps (no deletions)
1. **Rewire runtime canonical action:** fix `spectre/actions/dashboard-actions/process-triggers.sh` to dispatch allowlisted actions via `spectre run <job>` (or canonical impl), keeping allowlist/security behavior; update/add focused tests. Re-run `bash tests/run_tests.sh` / relevant tests.
2. **Decide ML canonical layout:** confirm whether `scripts/ml-anomaly/*` has/needs canonical equivalents under `spectre/actions/` or `spectre/ml-anomaly/`; rewire CI/tests/docs/systemd templates before any `scripts/ml-anomaly` removal.
3. **CI/test rewiring plan (batched):** map `.github/workflows/*` and `tests/run_tests.sh` + high-coupling tests to canonical paths/`spectre` commands. Do in small batches with green gates.
4. **Tier A prep:** resolve registry/config-consistency/tests for top-level `prometheus/*-exporter.sh`, then perform Tier A as a small, reviewable change.
5. **Tier B (`scripts/` forwarders) only after A/rewires:** batch directory-by-directory, `spectre actions verify` + tests green after each batch.
6. **`install.sh` rewrite** tracked separately (aligned with §8.2); README already warns.

## Acceptance (C1.1)
- [x] Reference audit completed with `rg` + targeted review.
- [x] Hits classified into must-rewire / should-update / historical.
- [x] No deletions, no host/scheduler changes made.
- [x] `spectre actions verify` remained **0 findings** (checked before audit).