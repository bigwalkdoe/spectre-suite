# spectre-security Retirement — Systematic Execution Status

**Date:** 2026-11-07 (executed stepwise; repo-only/additive where safe)  
**Coordination:** cross-repo + host + org. **No destructive host mutations, no spectre-security repo deletion/archive on GitHub, no systemd repointing performed without explicit confirmation.**  
**Canonical plan:** `2026-11-07-spectre-security-ops-dedupe-retirement-plan.md`

## Step 1 — Decide & document (coordination) — **decisions recorded (2026-11-07)**
- **Decisions (confirmed):**
  - **Status:** **Superseded** (plan for retirement/read-only archival once per-capability checklist satisfied, coordinated)
  - **OPA governance:** **C now** (shared core + adapters) — define Spectre security contract + adapters (suite flat-baseline, spectre-security nested/test-data, k8s admission) and run core gates + adapter-specific tests; keep isolated paths separate from `data.security[k].deny` aggregation until explicitly integrated.
  - **SonarQube/ZAP/hosted services:** **Evaluate separately** (treat as operational deps to evaluate/disposition; do not retire with repo until decided)
- **Status as of 2026-11-07:** suite has absorbed baseline phase jobs/runner compat path, OPA Option A adapter-tested slices (backup/network/docker evidence+metadata/security-compliance boundaries), isolated k8s admission + versions-index reporting, `spectre_security_baseline_*` observability (exporter/alerts/dashboard/tests, `opa_compat_report_ok` report-ran semantics). CI/OPA gates **38/0**, `actions verify` green.
- **Remaining coordination:** concrete adapter/core schema/versioning work for path C, k8s admission/versions final placement + CI treatment (currently isolated), hosted infra disposition tracking, full dependency removal plan.

## Step 2 — Remove hard runtime dependency on the repo path — **repo prep done (graceful/explicit); asset promotion decision-dependent**
- **Decisions (confirmed 2026-11-07):**
  - **Approach:** **Keep explicit/optional with graceful fallback** — compat/isolated tools use `SPECTRE_SECURITY_ROOT` with clear errors/degradation when absent; **do not fail hard** in compat modes.
- **Finding:** `SPECTRE_SECURITY_ROOT` defaults to `/home/deon/dev/github/spectre-security` in compat/isolated tools (adapter report fallbacks, baseline runner/drift/exporter compat, k8s/versions reports). This is an **optional/compat dependency** by design.
- **Executed (additive):** improved graceful/explicit behavior and docs — `versions-index-report`/`kubernetes-admission-report` report explicit missing-root/path errors and remain isolated; dependency documented here and in governance/ops docs. Tests skip when spectre-security assets absent.
- **Not done (requires decision):** copying/promoting spectre-security OPA policies/versions/test-data into suite as canonical assets (governance decision under path C) if full removal is needed. Current approach keeps dependency explicit/versioned for compat-only paths.

## Step 3 — Per-capability parity + host repointing — **repo prep; host decisions recorded (migration pending approval)**
- **Decisions (confirmed 2026-11-07):**
  - **3a (host):** Legacy system `security-baseline-http-exporter.{service,timer}` is **masked/inactive**; no suite template found. **Executed:** created/enabled user timer `spectre-security-baseline-metrics.timer` → `spectre-security-baseline-metrics.service` running `spectre/monitoring/exporters/security-baseline-metrics-exporter.sh` (every 5 min, `~/.config/systemd/user/`), writing to `prometheus/business-metrics/security_baseline_metrics.prom` (verified: wrote metrics, `source=spectre_security`). Left masked legacy system units unchanged.
  - **3b (OPA path C / k8s):** **Keep k8s admission/versions isolated + separate CI for now** (not merged into `data.security[k].deny` aggregation). Path C core schema/adapters to be designed incrementally.
- **Repo-side (present):** `security/baseline/run` and phase jobs registered/verified; `prometheus/security-baseline-metrics-exporter` action + implementation registered; alerts/dashboard/docs/tests in place. Textfile dir: `prometheus/business-metrics` (scraped via node_exporter textfile collector).
- **Host migration:** suite user timer installed and active; masked legacy HTTP exporter untouched. No further host mutation performed.
- **Decision/gap:** concrete path C contract/schema/versioning, k8s+versions final CI integration (if ever), live infra input generation parity.

## Step 4 — Triage remaining 12 `/usr/local/bin` legacy scripts — **triaged (read-only); NO action taken**
**Evidence (2026-11-07):** after archiving `setup-backup-cron.sh` + `check-performance-wrapper.sh`, 12 files remain with `/home/deon/scripts` refs (root-owned, Jul 26, hashes differ from current spectre-security copies — likely installed legacy state).

| Script | Observed purpose (from head) | Risk | Suggested disposition (requires explicit confirmation) |
|---|---|---|---|
| `centralized-log-shipper.sh` | ships logs to remote Loki/S3; reads `/home/deon/scripts/logging/log-shipper.env`, scans `/home/deon/scripts/logs` | Medium — may be used manually; stale paths | Confirm manual/external use; if unused, archive to `/usr/local/bin/.archived-spectre-security-*` (0644). Migrate to suite/observability logging path if needed. |
| `container-logrotate.sh` | configures Docker daemon json-file log opts (`/etc/docker/daemon.json`, restarts Docker) and system logrotate for `/home/deon/scripts/logs` etc. | **High** — mutates Docker daemon config and restarts Docker; stale log paths | **Do not execute.** Confirm whether equivalent config is managed elsewhere; archive if unused. |
| `run-zap-scan.sh` | OWASP ZAP scan, reports to `/home/deon/scripts/security/reports` | Medium — runtime helper, stale report path | Confirm use; archive or replace with suite security scan action/output path. |
| `run-trivy-scan.sh` | Trivy image/fs/repo scans, reports to `/home/deon/scripts/security/reports` | Medium — overlaps suite security scanning/trivy-image-scan; stale paths | Confirm use; prefer suite `security/*/trivy-*` / baseline actions; archive if unused. |
| `setup-logging.sh` | starts Loki stack from `/home/deon/scripts/logging/docker-compose.loki.yml`, creates `/home/deon/scripts/logs` | **High** — deploys stack from legacy path | **Do not execute.** Archive unless actively used via known workflow; reconcile with suite/compose observability. |
| `setup-resource-monitoring.sh` | generates `/home/deon/scripts/performance/*` cost/resource scripts | **High** — generator targeting legacy paths | **Do not execute.** Archive unless confirmed needed. |
| `setup-opa-policies.sh` | installs OPA to `/usr/local/bin/opa`, generates policies under `/home/deon/scripts/security/opa` | **High** — generator; conflicts with suite-canonical `spectre/policies`/OPA governance | **Do not execute.** Archive; use suite OPA governance. |
| `setup-audit-logging.sh` | configures auditd/rules/rotation, references `/home/deon/scripts` paths | **High** — mutates system audit config | **Do not execute** without review. Confirm host audit config source of truth; archive if legacy. |
| `setup-security-scanning.sh` | installs Trivy, generates `/home/deon/scripts/security/run-trivy-scan.sh` + scan setup | **High** — generator/install + legacy paths | **Do not execute.** Prefer suite security actions; archive. |
| `setup-database-optimization.sh` | generates `/home/deon/scripts/performance/pg-vacuum.sh`; hardcodes `guardrail-ai-postgres-1` | **High** — generator targeting legacy paths + app-specific container | **Do not execute.** Archive unless confirmed. |
| `setup-secrets-management.sh` | sets up env-based secrets under `/home/deon/.secrets` (and possibly Vault mode) | **High** — secrets/config handling | **Do not execute** without review. Confirm if `.secrets` pattern is in active use; archive/migrate carefully. |
| `setup-intrusion-detection.sh` | installs/configures Fail2Ban/Wazuh/AIDE | **High** — mutates host security controls (IDS/IPS/AIDE) | **Do not execute** without review. Confirm active IDS/IPS source of truth; reconcile with suite security baseline/hardening before any archive. |

**Rule:** no archive/remove/replace without explicit per-file (or explicitly scoped batch) confirmation. `setup-intrusion-detection.sh`, `setup-audit-logging.sh`, `setup-logging.sh`, `container-logrotate.sh` touch active security/daemon/stack config — treat with extra caution.

## Step 5 — Archive spectre-security read-only (coordinated) — **NOT executed**
**Preconditions (all required):** steps 1–4 completed/confirmed; retirement checklist satisfied per capability; no required consumers of the repo path remain (or dependency explicitly versioned/accepted); host schedulers/units repointed; GitHub/org workflow coordination complete.
**Actions (when confirmed):**
- Ensure local clone has no needed uncommitted state (spectre-security currently has untracked `AGENTS.md` — review separately).
- Tag/release a final retirement marker in spectre-security; update README to “archived/read-only, superseded by spectre-suite” with pointers.
- Archive GitHub repo (`bigwalkdoe/spectre-security`) after coordination; retain git history.
- Keep/adjust local clone only if compat tools still intentionally depend on it; otherwise remove local path after dependency removal is complete and verified.
- Update Phase 4/ops checklist evidence and suite docs.

**I did not archive/delete the spectre-security repo (local or GitHub).**
