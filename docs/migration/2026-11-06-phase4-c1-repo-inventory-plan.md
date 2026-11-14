# Phase 4 / C1 — Repo Inventory Plan (NO DELETIONS)

**Status (original):** Draft inventory/plan only (2026-11-06). **No `git rm`, no file deletions, no host changes.**  
**Status (2026-11-07):** **C1 complete on `main`.** Tracked legacy `scripts/` tree removed via confirmed, batched B1/B2 rewires + B3 preps/deletions; OPA canonicalized to real `spectre/policies/`. CI green on `4c211c9` (Authorship, Lint & Config Validation incl. OPA, Spectre Suite CI/CD, Automated Security Scanning incl. OPA, CodeQL, ML Anomaly Detection Test, Full Test Suite). `git ls-files scripts` = **0**.  
**Branch/context (original):** `feat/consolidation-phase1-shims` @ post-Phase 2/3 (host schedulers repointed; `spectre actions verify` → 0 findings).  
**Spec refs:** `docs/superpowers/specs/2026-10-05-spectre-consolidation-design.md` §8.4 Phase 4 (“Remove shims…”), §8.3 (forwarders).

## Goal
Produce a safe, reviewable plan for C1: identify legacy compatibility copies under repo-root `scripts/` and `prometheus/*.sh` relative to canonical `spectre/actions/` and `spectre/monitoring/exporters/`, confirm reference/dependency safety, then remove only truly redundant paths in a follow-up (explicitly confirmed) change.

## Evidence snapshot (inventory method)
Command pattern (recorded): walk `scripts/**/*.sh`; classify each as `forwarder` if it contains the Phase 1 forwarder markers / small delegated stub pointing at `spectre/actions`, else `script`; compare byte-for-byte to `spectre/actions/<relpath>` when present. Inspect `prometheus/*.sh` vs `spectre/monitoring/exporters/`.

## Findings

### 1) `scripts/` → `spectre/actions/` (74 `.sh` files inventoried)
| Metric | Value |
|---|---|
| Total `.sh` under `scripts/` | 74 |
| Canonical counterpart exists under `spectre/actions/` | 74/74 |
| Classified as “forwarder-like” by marker heuristic | 0/74 (heuristic did not match marker text in the way expected) |
| Byte-identical to canonical | 0/74 |
| Typical size | ~460–484 bytes (small) |

**Manual spot checks show these are Phase 1 forwarders** (not full implementations), e.g.:
- `scripts/check-config-consistency.sh`, `scripts/backups/run-missed-backups.sh`, `scripts/maintenance/cleanup-*.sh`, `scripts/systemd/label-exec-context.sh` all contain `# Phase 1 forwarder ...`, compute `SPECTRE_REPO_ROOT` by finding `spectre/actions`, and delegate to `$SPECTRE_REPO_ROOT/spectre/actions/<relpath>`.
- Canonical implementations live in `spectre/actions/<same relpath>` (e.g. config-consistency 352 lines vs 7-line forwarder; run-missed-backups full logic in actions).

**Interpretation:** `scripts/` is effectively a **legacy compatibility/forwarder tree** mirroring `spectre/actions/` paths. The earlier heuristic undercounted because marker matching was too narrow; treat classification as **forwarder (verified by spot check pattern)** pending per-file confirmation during C1 execution.

### 2) `prometheus/` top-level exporters
| Path | Type (verified) | Canonical |
|---|---|---|
| `prometheus/business-metrics-exporter.sh` | 7-line forwarder (`# Phase 1 forwarder: delegate to spectre/actions impl`) | `spectre/monitoring/exporters/business-metrics-exporter.sh` (and actions/registry targets as applicable) |
| `prometheus/security-metrics-exporter.sh` | 7-line forwarder | `spectre/monitoring/exporters/security-metrics-exporter.sh` |

### 3) Host/scheduler state (relevant safety context)
- `spectre actions verify`: **0 findings** (no `legacy-path` / `unregistered`).
- Crontab and observed systemd units invoke `/usr/local/bin/spectre run <job>` (not repo `scripts/` or top-level `prometheus/*.sh`).
- `~/scripts` absent. **Remaining host risk is not scheduler legacy-path**, but any local/manual tooling, docs, CI, tests, or external references to `scripts/...` / `prometheus/*-exporter.sh` inside this repo.

## C1 execution plan (future, requires explicit confirmation before any deletion)

### C1.0 — Preconditions / guardrails
- [ ] Work on a dedicated change/commit; keep reversible.
- [ ] Re-run `PYTHONPATH=$PWD python3 -c "from spectre.dispatch.verify import verify, read_host_inventory; ..."` / `spectre actions verify` (expect 0 findings).
- [ ] Run `bash tests/run_tests.sh` green (19/19) before and after.
- [ ] **No host changes.** No scheduler edits.

### C1.1 — Reference audit (must complete before deleting any path)
Search for references to legacy repo paths (exclude generated/vendor/cache as appropriate):
- [ ] `rg -n '\bscripts/' --glob '*.sh' --glob '*.py' --glob '*.yml' --glob '*.yaml' --glob '*.md' --glob '*.service' --glob '*.timer' --glob 'Dockerfile*' --glob 'Makefile*'` (review each hit: runtime vs docs/historical).
- [ ] `rg -n 'prometheus/(business-metrics-exporter|security-metrics-exporter)\.sh'`
- [ ] Check CI workflows under `.github/`, install scripts, `install.sh`, systemd templates in repo, docs that give operator commands, and any tests not covered above.
- [ ] Classify hits: **must keep/rewire**, **historical doc (update text, keep path mention only if intentional)**, or **safe to remove with path**.

### C1.2 — Deletion candidates (proposed order, only after C1.1)
1. **Tier A (lowest risk, after reference audit):** `prometheus/business-metrics-exporter.sh`, `prometheus/security-metrics-exporter.sh` if no in-repo runtime/CI/install reference requires them; canonical exporters already under `spectre/monitoring/exporters/`.
2. **Tier B:** `scripts/` forwarder tree entries confirmed redundant — **prefer batched, directory-by-directory** (e.g. `scripts/systemd/`, then `scripts/maintenance/`, etc.), re-running tests/verify after each batch. Do **not** remove any path still referenced by runtime code, install, CI, or user-facing docs without rewiring.
3. **Tier C (defer):** any `scripts/` path that is not a pure forwarder or has no canonical counterpart (none found in 74-file scan, but re-verify), or paths referenced by external/manual workflows.

### C1.3 — Rewire rules (when a reference must remain functional)
- Prefer `spectre run <job>` for operator/scheduler-facing instructions.
- For library/implementation paths in code/tests, prefer `spectre/actions/<relpath>` (canonical).
- Do not reintroduce `/usr/local/bin` script installs (§8.2).

### C1.4 — Acceptance for a C1 deletion commit
- [ ] `spectre actions verify` → 0 findings.
- [ ] `bash tests/run_tests.sh` → 19/19 (or current full-suite baseline).
- [ ] `git grep` shows no unintended stale runtime references to removed paths.
- [ ] Commit message documents what was removed and why safe (verify clean, refs audited).

## Open questions / risks
- **Inventory heuristic:** reported 0/74 “forwarder-like” due to narrow matching, but spot checks confirm Phase 1 forwarders. C1.1/C1.2 should use `head`/marker check per file (or fix the heuristic) before bulk decisions.
- **Doc/historical references:** many docs intentionally mention `scripts/...` as historical paths; update wording rather than breaking meaning.
- **External consumers:** anything outside this repo (user shell aliases, notes, other repos) may still reference `scripts/` — out of scope for repo-only C1; verify shows schedulers are migrated.
- **`prometheus/*.sh` naming:** confirm registry/monitoring code paths and any compose/build contexts before removing top-level forwarders.

## Recommendation
Proceed with **C1.1 reference audit only** as the next confirmed step (no deletions), then propose Tier A as a small, reviewable PR/commit. Keep `scripts/` removal batched and gated on green tests + verify after each batch.

## C1 completion (2026-11-07)

**Outcome:** Complete. Reference audit performed in practice through evidence-backed B3-prep/batch proposals; active runtime/CI/test/example/exporter/installer refs rewired to canonical `spectre/actions/*`, `spectre/monitoring/exporters/*`, `spectre/policies/*`, and/or `spectre run` dispatch. Tracked legacy `scripts/` removed in confirmed batches (1–10a+10b) plus OPA Steps A–B. Top-level `prometheus/*-exporter.sh` Tier A forwarders had been removed earlier (`951e5e3`).

**Key commits:** `54c9d6c` (B2), `bd9eb08`–`13f0935` (B3 preps/batches 1–10a+10b, including OPA-adjacent work), `010ea7b` (OPA Step A: real `spectre/policies/`), `0dfe7a1` (OPA Step B: removed `scripts/security/opa/*`), `4c211c9` (fix: `tests/test_ml.py` → `spectre/actions/ml-anomaly`).

**Verification:** CI all green on `4c211c9`; `git ls-files scripts` = 0. `opa check spectre/policies/` passed locally during Step A.

**Notes:** Untracked local leftovers may remain on disk (e.g. `scripts/ml-anomaly/venv/`); not tracked/deleted. Historical `docs/migration/*` and `docs/superpowers/*` records retain old path mentions as context. Optional follow-up: CI guardrail preventing reintroduction of tracked `scripts/` paths. Revisit `docs/superpowers/specs/2026-10-05-spectre-consolidation-design.md` for any Phase 4 work beyond C1.
