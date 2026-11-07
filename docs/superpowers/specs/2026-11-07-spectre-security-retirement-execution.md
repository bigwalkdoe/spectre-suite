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
- **Finding:** `SPECTRE_SECURITY_ROOT` defaults to `~//dev/github/spectre-security` in compat/isolated tools (adapter report fallbacks, baseline runner/drift/exporter compat, k8s/versions reports). This is an **optional/compat dependency** by design.
- **Executed (additive):** improved graceful/explicit behavior and docs — `versions-index-report`/`kubernetes-admission-report` report explicit missing-root/path errors and remain isolated; dependency documented here and in governance/ops docs. Tests skip when spectre-security assets absent.
- **Not done (requires decision):** copying/promoting spectre-security OPA policies/versions/test-data into suite as canonical assets (governance decision under path C) if full removal is needed. Current approach keeps dependency explicit/versioned for compat-only paths.

## Step 3 — Per-capability parity + host repointing — **repo prep; host decisions recorded (migration pending approval)**
- **Decisions (confirmed 2026-11-07):**
  - **3a (host):** Legacy system `security-baseline-http-exporter.{service,timer}` is **masked/inactive**; no suite template found. **Executed:** created/enabled user timer `spectre-security-baseline-metrics.timer` → `spectre-security-baseline-metrics.service` running `spectre/monitoring/exporters/security-baseline-metrics-exporter.sh` (every 5 min, `~/.config/systemd/user/`), writing to `prometheus/business-metrics/security_baseline_metrics.prom` (verified: wrote metrics, `source=spectre_security`). Left masked legacy system units unchanged.
  - **3b (OPA path C / k8s):** **Keep k8s admission/versions isolated + separate CI for now** (not merged into `data.security[k].deny` aggregation). Path C core schema/adapters to be designed incrementally.
- **Repo-side (present):** `security/baseline/run` and phase jobs registered/verified; `prometheus/security-baseline-metrics-exporter` action + implementation registered; alerts/dashboard/docs/tests in place. Textfile dir: `prometheus/business-metrics` (scraped via node_exporter textfile collector).
- **Host migration:** suite user timer installed and active; masked legacy HTTP exporter untouched. No further host mutation performed.
- **Decision/gap:** concrete path C contract/schema/versioning, k8s+versions final CI integration (if ever), live infra input generation parity.

## Step 4 — Triage remaining 12 `/usr/local/bin` legacy scripts — **COMPLETE (evidenced)**
**Confirmed/evidenced (2026-11-07):**
- Earlier: `setup-backup-cron.sh` (sha256 `82b1908517...d8c7`) + `check-performance-wrapper.sh` (sha256 `29365ac6ce...8896`) archived.
- Now: all 12 remaining scripts archived to `/usr/local/bin/.archived-spectre-security-20261107/` (0644) with SHA256s recorded:
  - `centralized-log-shipper.sh` `d8e7a275...3dad`
  - `container-logrotate.sh` `c906cc1e...17ac`
  - `run-zap-scan.sh` `a12e62ac...8b57`
  - `run-trivy-scan.sh` `c40fd822...7420`
  - `setup-audit-logging.sh` `de10cc6c...7e7b`
  - `setup-database-optimization.sh` `87e8bc23...a754`
  - `setup-intrusion-detection.sh` `5e123526...2a6e`
  - `setup-logging.sh` `735d25d6...ea7d`
  - `setup-opa-policies.sh` `3e8e17e9...8ad9` (conflicts with suite OPA governance)
  - `setup-resource-monitoring.sh` `616c18f7...22fe`
  - `setup-secrets-management.sh` `b5ee1663...5ef0`
  - `setup-security-scanning.sh` `5129ee4c...8147`
- **Verification:** spot-check removed; `rg -l ~//scripts /usr/local/bin` → **no refs remain**. Archive contains 14 files total (all non-executable). Note: archiving prevents execution from `/usr/local/bin` but does not undo any prior system changes made by these scripts.

## Step 5 — Archive spectre-security read-only (coordinated) — **NOT executed**
**Preconditions (all required):** steps 1–4 completed/confirmed; retirement checklist satisfied per capability; no required consumers of the repo path remain (or dependency explicitly versioned/accepted); host schedulers/units repointed; GitHub/org workflow coordination complete.
**Actions (when confirmed):**
- Ensure local clone has no needed uncommitted state (spectre-security currently has untracked `AGENTS.md` — review separately).
- Tag/release a final retirement marker in spectre-security; update README to “archived/read-only, superseded by spectre-suite” with pointers.
- Archive GitHub repo (`bigwalkdoe/spectre-security`) after coordination; retain git history.
- Keep/adjust local clone only if compat tools still intentionally depend on it; otherwise remove local path after dependency removal is complete and verified.
- Update Phase 4/ops checklist evidence and suite docs.

**I did not archive/delete the spectre-security repo (local or GitHub).**
