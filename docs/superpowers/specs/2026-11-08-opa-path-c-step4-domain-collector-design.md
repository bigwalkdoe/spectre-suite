# OPA Path C — Step 4: Suite-Native Domain Collector (design/scope)

**Date:** 2026-11-08  
**Status:** design/scope (spike-ready; no policy/gate/aggregation changes)  
**Builds on:** live-infra snapshot v0 + normalizer (steps 1–3 complete, parity fixtures green)  
**Invariants (must hold):** `data.security[k].deny[m]` canonical; `opa check`; empty-input fail-closed ≥38; `baseline.json` 0 denials; k8s admission/versions isolated (no aggregation); compat/normalizer report-only/non-gating where applicable.

## 1. Goal
Implement **one** suite-native, versioned evidence collector that produces a `live_infra_snapshot/v0`-compatible nested snapshot for a **single domain**, normalized via `live-infra-normalize.py` / adapter rules, with fixture-based parity proof. This reduces dependence on archived/legacy `current-infrastructure.json` producers without changing core policy semantics.

## 2. Selected initial domain (scope boundary)
**Domain:** `compliance` + `backup` evidence subset (mapped, unambiguous fields only) — the smallest domain where suite-native signals are most defensible and mappings already exist.

| Nested field (producer output) | Suite mapping (existing) | Evidence source (proposed) | Parity proof |
|---|---|---|---|
| `compliance.firewall_enabled` | `firewall_enabled` | host check (e.g., `firewall-cmd`/nftables state) — read-only | fixture + optional host-gated test |
| `compliance.ssh_password_auth` | `ssh_password_auth` | `sshd -T`/config parse (read-only) | fixture + optional host-gated test |
| `compliance.audit_logging_enabled` | `audit_logging_enabled` | `auditd`/journald audit state (read-only) | fixture + optional host-gated test |
| `compliance.intrusion_detection_active` | `intrusion_detection_active` | presence/service state (read-only); **must not** invent `fail2ban_*` | fixture |
| `compliance.file_integrity_monitoring` | `file_integrity_monitoring` | AIDE/FIM tool state if present (read-only) | fixture |
| `backup.encrypted` | `backup_encryption_enabled` | restic/config markers or explicit config (read-only) | fixture |
| `backup.retention_days` | `backup_retention_days` (int) | policy/config; non-int → absent/fail-closed | fixture |
| `backup.offsite_replication` | `backup_offsite_enabled` | offsite marker/config (read-only) | fixture |

**Explicitly out of initial scope:** `docker[]` live inspection, `network.open_ports`/segmentation mapping inventions, any field in `suite_controls_never_invented_examples`, k8s admission aggregation.

## 3. Producer contract
- **Entrypoint (proposed):** `spectre/actions/security/baseline/live-infra-collect.py` (or domain-specific module) with `--domain compliance,backup --output <snapshot.json> --format v0`.
- **Output:** valid `live_infra_snapshot/v0` envelope (`contract_version`, `source`, `generated_at`, plus requested domains; omitted domains may be empty objects/absent per schema-compat rules — schema currently requires all four top-level domains; producer must emit all four, using empty/default-safe containers for uncollected domains).
- **Safety:** read-only host inspection; no `sudo` required by default (if privileged evidence is unavailable, emit **absent**/conservative values that preserve fail-closed behavior — never invent “compliant”).
- **Determinism for tests:** support `--from-fixture`/input injection or pure functions so CI does not depend on host state.

## 4. Parity & validation plan
1. **Unit fixtures:** fixed evidence inputs → expected nested snapshot → `live-infra-normalize` → expected canonical flat fields (only mapped fields).
2. **OPA parity (gated-safe):** adapted flat input evaluated with `opa eval --data spectre/policies` against `data.security[k].deny[m]` in tests; assert behavior is consistent with mapping (fail-closed for absent/unmapped). No change to global 38/0 invariants except tests run in isolated inputs.
3. **Host-gated smoke (optional, non-CI):** compare collector output structure on this host; never commit host-specific evidence as policy truth.
4. **Schema/contract:** producer output validates against `tests/fixtures/live_infra_snapshot/live_infra_snapshot.v0.schema.json`.

## 5. Risks / mitigations
- **Overclaiming compliance:** collector reports “enabled/true” without strong evidence. *Mitigation:* default absent/false only when evidence is explicit; document evidence strength; prefer absent (fail-closed) when uncertain.
- **Privileged checks:** some evidence needs root. *Mitigation:* degrade to absent + report note; no sudo in automated paths without explicit design.
- **Scope creep into docker/network:** *Mitigation:* strict domain flag; docker/network emitted as empty structures in initial slice unless explicitly implemented with fixtures+parity.

## 6. Implementation slices (recommended)
1. **Slice A (testable, no host deps):** pure normalization/producer helpers + fixture-driven collector core + schema validation + unit/OPA tests.
2. **Slice B (optional, host-gated):** read-only local probes for compliance/backup markers behind explicit flags; skipped in CI.
3. **Slice C (integration):** wire into `SECURITY_OPA_COMPAT`/baseline flow as an **optional, report-only** source behind a flag (non-gating), with provenance.

## 7. Acceptance for “step 4 started/complete (initial domain)”
- [x] v0 snapshot producer for `compliance`+`backup` (Slice A) with fixtures and tests — `spectre/actions/security/baseline/live-infra-collect.py`, `tests/test_live_infra_collect.py` (fixture-driven, no host deps).
- [x] `live-infra-normalize` + adapter parity proven on fixtures.
- [x] No changes to `data.security[k].deny` aggregation, core CI gate semantics, or k8s isolation.
- [x] All relevant existing OPA/contract tests remain green; new tests added additively (CI `opa-isolated-k8s` gates snapshot/normalizer/collector tests).
