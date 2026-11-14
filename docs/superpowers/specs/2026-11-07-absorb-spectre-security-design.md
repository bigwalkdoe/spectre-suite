# Absorb `spectre-security` into `spectre-suite` (suite-as-canonical) — Design Draft

**Date:** 2026-11-07  
**Status:** **complete (all 5 phases delivered; operator decisions remain)**  
**Goal:** Make `spectre-suite` the canonical home for security baseline/drift/SBOM/compliance/OPA capabilities currently owned by `spectre-security`, while preserving mature workflows, evidence quality, and CI gates.

## 1. Intent
- **Single CLI/dispatch/provenance surface:** security capabilities run as `spectre run <job>` (registry jobs/groups), with explicit `sudo`, `mutates`, `timeout`, and `concurrency`.
- **One policy source:** unify OPA policies, tests, and compliance mapping under canonical suite paths.
- **Normalized config/env:** converge on suite conventions (`SPECTRE_HOME`/repo paths, baseline/evidence dirs, secrets paths) with compatibility shims where needed.
- **Unified metrics:** publish non-ambiguous names/labels for agent runtime + baseline/drift/SBOM evidence.
- **Retire overlap safely:** overlapping top-level scripts/installers in `spectre-security` and legacy host artifacts retired only after parity/coordination.

## 2. Current state (observed 2026-11-07)
### `spectre-suite` (canonical target)
- Dispatch/registry/provenance: `spectre/dispatch/*`, `registry_data.json` (67 jobs), `spectre actions verify` clean.
- Security actions: `spectre/actions/security/*` (hardening, API/docker hardening, dependency/docker scans, IDS/IPS, integration/rate-limiting). `security/run-security-hardening` registered (`sudo`, `mutates`, `concurrency=forbid`).
- OPA: `spectre/policies/*.rego` + `baseline.json`. Packages use `security.*`/`import rego.v1` style (e.g. `security.docker`, `security.compliance`). CI (`lint.yml`) runs `opa check spectre/policies/`, fail-closed count on empty input (`count([m | data.security[k].deny[m]])` >= 38), and baseline eval with no denials.
- Monitoring/metrics: `spectre/monitoring/exporters/*`, dashboard/prometheus config; doc-drift/config checks in CI.

### `spectre-security` (source, local at `~//dev/github/spectre-security`)
- **Baseline orchestrator:** `security/baseline-runner.sh` phases: (1) OPA validate + `test-opa-policies.sh`, (2) hardening (`run-security-hardening.sh`), (3) Trivy FS, (4) Wazuh status, (5) AIDE, (6) Gitleaks, (7) optional Trivy image (`IMAGE_NAME`), (8) SBOM (`generate-sbom.sh`), (9) drift (`drift-detection.sh`), (10) alerting (`alerting.sh`). Logs/evidence under `security/logs/`.
- **OPA:** `security/opa/policies/*` includes `*_test.rego` and policies like `docker-security.rego` (`package docker.security`), `security-compliance.rego` (`package security.compliance`), `backup-policy.rego`, `network-security.rego`, `kubernetes-admission.rego`; plus `versions/*` with `metadata.json`/`index.json`; `evaluate-policies.sh` builds live infra input and evaluates. `test-opa-policies.sh` uses different data contracts/queries (e.g. `data.backup.policy.deny`, `data.docker.security.deny`, `current-infrastructure.json`).
- **Baseline metrics/exporters:** `security-baseline-exporter.sh`, fast/http variants, Python HTTP exporter, systemd service/timer units, Grafana dashboard, workflow `security-baseline.yml`. Metrics use `security_baseline_*` prefix (OPA pass/fail/total, phase durations, Trivy/Gitleaks/AIDE/Wazuh/SBOM/drift/image statuses).
- **Other assets:** Trivy/ZAP/Sonar compose/artifacts, trivy reports, remediation/update-baseline scripts, top-level overlaps (`run-security-hardening.sh`, `setup-backup-cron.sh`, `archive-project.sh`, etc.).

### Host/install overlap (fedora, 2026-11-07)
- `/usr/local/bin` contains legacy `~//scripts`-referencing wrappers/installers matching `spectre-security` filenames but **hashes differ** from current repo copies; **no active scheduler refs found** in checked cron/systemd/user-unit locations. Treat as **cross-repo/host coordination** (do not delete blindly). `setup-backup-cron.sh` in `/usr/local/bin` would regress clean `spectre run` crontab if executed.

## 3. Recommended direction (pragmatic, 2026-11-07)
- **Clarify data sources (distinct signals):** treat **Spectre agent runtime** findings/availability and **spectre-security baseline pipeline** (OPA test/drift/SBOM/scan phase/evidence) as separate signals. Name/label metrics so `agent down`, `no scan recorded/never run`, `unknown` (cannot determine), `stale` (evidence older than policy), `drift detected`, and `clean scan` are never conflated.
- **Unify OPA governance (highest drift risk):** pick one canonical policy+test+compliance-mapping source (A-contract or C-shared-core). Keep suite CI fail-closed gate green during migration; adapt/bridge security-repo tests/contracts explicitly.
- **Execution/scheduling surface:** make `spectre-suite` canonical for host runs (`spectre run ...`, provenance, `actions verify`). Start with **A/D hybrid**: suite schedules/orchestrates; `spectre-security` may own deep evidence generation where strongest until contracts stabilize; evolve toward B/C.
- **De-duplicate ops scripts deliberately:** prefer suite’s canonical registry/health/catch-up/restic semantics; migrate only gaps; document/retire parallels to avoid two truths. Coordinate host/systemd/exporter retirement (explicit confirmation per host change).

## 4. Key divergences / risks
- **OPA contract mismatch:** suite CI depends on `data.security[k].deny[m]` over flat `baseline.json`/live input conventions and `import rego.v1` packages; spectre-security policies/tests use different package names and nested input shapes. Naive merge can break suite’s fail-closed CI gate and/or security-repo test semantics.
- **Evidence semantics:** baseline/SBOM/drift/scan outputs have operational meaning (logs, reports, metrics, alerts). Migration must preserve evidence paths/format compatibility where consumed, or version them explicitly.
- **Mature workflows:** spectre-security has CI/workflows, systemd exporters/timers, and host-installed behavior; retirement requires parity proof.
- **Privilege/safety:** baseline phases mix read-only checks, privileged probes, container/network tooling, and alerting. Registry jobs must declare accurate `sudo`/`mutates`/`concurrency`.

## 4. Target mapping (conceptual)
| Source capability (`spectre-security`) | Canonical target (`spectre-suite`) | Form |
|---|---|---|
| `security/baseline-runner.sh` phases | `spectre/actions/security/baseline/*` + registry group/jobs | Additive first; later decompose phases |
| OPA validate/evaluate/tests, policies, k8s admission, versions/metadata | `spectre/policies/*` (+ tests/mapping/check scripts as needed) | Unified tree with explicit compatibility layer |
| `drift-detection.sh`, `update-baseline.sh` | `spectre/actions/security/baseline/` or `spectre/actions/security/` | Registry jobs, evidence outputs normalized |
| `generate-sbom.sh`, image/fs scan orchestration | `spectre/actions/security/` (scan/sbom jobs) | Preserve report formats; integrate exporters |
| `alerting.sh`, remediation helpers | `spectre/actions/security/` | Optional jobs/hooks; no secret leakage |
| baseline exporters/services/timers/dashboard | `spectre/monitoring/exporters/*`, dashboard/config, systemd unit templates/installers | Non-ambiguous metric names/labels |
| overlapping top-level scripts/installers | retire/replace in `spectre-security` and host after parity | Coordinated, confirmed |

## 5. Phased implementation (additive-first)
1. **Inventory & compatibility (this slice foundation):** document mapping (done here), add canonical baseline entrypoint(s) in suite without breaking existing jobs/CI. *(started 2026-11-07: `spectre/actions/security/baseline/baseline-runner.sh`, registry job `security/baseline/run`)*
2. **Baseline phase parity:** port/adapt phase helpers (OPA compat/test adapter, hardening integration, Trivy/Gitleaks/AIDE/Wazuh/SBOM/drift/image/alert) with suite path/env normalization; preserve evidence files and exit semantics where consumed.
3. **OPA unification:** define canonical policy contract + compatibility adapter; migrate/merge policies & `*_test.rego`; reconcile `baseline.json`/infra input generation; keep suite CI fail-closed gate green throughout (adjust gate only with deliberate, tested changes).
4. **Metrics/exporters:** align `security_baseline_*` (and/or `spectre_security_*`) names/labels; add/update exporters and Grafana/dashboard config; avoid ambiguous duplicates.
5. **Retire overlaps:** after parity evidence, retire `spectre-security` overlapping scripts/installers and coordinate host `/usr/local/bin`/systemd cleanup (explicit confirmation per host change). Archive/read-only `spectre-security` as appropriate.

## 6. Config/env normalization (target)
- `SPECTRE_REPO_ROOT` / suite checkout root (default: detected from script location).
- `SPECTRE_HOME` / XDG state for evidence/logs (default: `${XDG_STATE_HOME:-$HOME/.local/state}/spectre`).
- `SECURITY_BASELINE_LOG_DIR`, `SECURITY_BASELINE_REPORT_DIR` overrides.
- `SPECTRE_SECURITY_ROOT` optional compatibility source for not-yet-ported helpers (explicit opt-in; never required for core suite jobs).
- Never print secrets; preserve existing env overrides.

## 7. CI/evidence preservation
- Keep existing `spectre/actions verify`, doc/config checks, and OPA fail-closed/baseline checks green at every step.
- Add tests/checks for new baseline jobs (syntax, registry consistency, and—where safe—adapter/contract tests).
- Evidence outputs (logs/reports/SBOM/drift/metrics) must be documented; breaking format/metric changes require versioned names/labels and migration notes.

## 8. Open questions
1. **OPA canonical contract:** keep suite’s `data.security[k].deny[m]`/`baseline.json` as canonical and add adapters for security-repo tests, or define a new unified schema with migration?
2. **Kubernetes admission policies/versions/index:** keep under `spectre/policies/k8s` or a dedicated subpath with version metadata?
3. **SBOM/report storage:** local state only vs committed artifacts vs CI artifacts/retention policy.
4. **Host systemd timers/exporters:** migrate units to canonical suite installers/templates in the same slice or a later ops slice?
5. **`spectre-security` retirement boundary:** which capabilities remain external (e.g., SonarQube/ZAP infra) vs fully absorbed?

## 9. Progress log
- 2026-11-07: Created this draft. Added additive canonical baseline runner `spectre/actions/security/baseline/baseline-runner.sh` and registry entry `security/baseline/run` (foundation; phase helpers/OPA compatibility/metrics unification follow in subsequent slices). No changes made to `spectre-security` repo; no host installer deletions.
- 2026-11-14: **All 5 phases delivered.** Phase 1 (path fix + tests + suite wiring), Phase 2 (14 baseline phase helpers all registered + executed end-to-end on host), Phase 3 (OPA Path C: shared core + adapters, k8s/versions isolated, 67/67 tests pass), Phase 4 (metrics/exporters reconciled: 16 `spectre_security_baseline_*` alerts, Grafana dashboard, exporter tests), Phase 5 (retirement: spectre-security archived, host legacy scripts archived, `actions verify` clean). **Remaining:** operator decisions on SonarQube/ZAP/hosted-services disposition and any further host repointing — no further destructive actions without explicit confirmation.