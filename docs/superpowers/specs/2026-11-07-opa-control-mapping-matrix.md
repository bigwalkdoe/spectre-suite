# OPA Control Mapping Matrix (Option A: suite contract canonical)

**Date:** 2026-11-07  
**Purpose:** Map spectre-security OPA assets/tests to `spectre-suite` canonical controls (`spectre/policies/*.rego`, `data.security[k].deny[m]`, flat `baseline.json` contract). Supports adapters and incremental porting without breaking CI gates.

## 1. Suite canonical CI gates (must remain green)
- `opa check spectre/policies/`
- Empty input `{}`: `count([m | data.security[k].deny[m]]) >= 38` (fail-closed; **38 controls** across 8 packages)
- `spectre/policies/baseline.json`: no denials

## 2. Suite control inventory (38 denials)
| Package | Controls (input fields) | Count |
|---|---|---:|
| `security.audit` | `audit_logging_enabled`, `audit_retention_days` (>=90), `sudo_logging_enabled` | 3 |
| `security.backups` | `backup_encryption_enabled`, `backup_retention_days` (>=7), `backup_offsite_enabled`, `backup_verification_enabled`, `database_backups_enabled`, `docker_volume_backups_enabled` | 6* |
| `security.compliance` | `security_baseline_compliant`, `cis_benchmarks_followed`, `pci_dss_compliant`, `security_assessments_scheduled`, `patch_management_active` | 5 |
| `security.docker` | `docker_not_root`, `docker_no_new_privileges`, `docker_userland_proxy_disabled`, `docker_resource_limits`, `docker_privileged_disabled` | 5 |
| `security.encryption` | `encryption_at_rest_enabled`, `encryption_in_transit_enabled`, `tls_configured`, `certificate_monitoring_enabled`, `key_rotation_enabled` | 5 |
| `security.firewall` | `firewall_enabled`, `ssh_password_auth==false`, `ssh_root_login==false`, `fail2ban_active` | 4 |
| `security.intrusion_detection` | `intrusion_detection_active`, `file_integrity_monitoring`, `fail2ban_configured`, `log_monitoring_enabled`, `alert_thresholds_configured` | 5* |
| `security.network` | `network_segmentation_enabled`, `dmz_isolated`, `internal_no_internet`, `vpn_enabled`, `ddos_protection_enabled` | 5 |

\*Verify exact deny-rule count per file when modifying; CI’s authoritative check is the 38-count gate.

## 3. spectre-security → suite mapping (adapter targets)

Source: `security/opa/policies/*`, `test-opa-policies.sh`, `test-data/current-infrastructure.json` (nested: `docker[]`, `network{}`, `compliance{}`, `backup{}`).

| spectre-security source | Legacy package/query | Nested input path (example) | Suite canonical field(s) | Adapter notes |
|---|---|---|---|---|
| `security-compliance.rego` | `security.compliance` (legacy semantics differ) | `compliance.firewall_enabled` | `firewall_enabled` (and compliance context) | Map where names align; suite’s `security.compliance` uses `security_baseline_compliant/cis/pci/...` — **not 1:1** |
| 〃 | 〃 | `compliance.ssh_password_auth` | `ssh_password_auth` | Suite expects `false` for secure state |
| 〃 | 〃 | `compliance.audit_logging_enabled` | `audit_logging_enabled` | Direct |
| 〃 | 〃 | `compliance.intrusion_detection_active` | `intrusion_detection_active`, `fail2ban_active`? | Partial; fail2ban is separate suite control |
| 〃 | 〃 | `compliance.file_integrity_monitoring` | `file_integrity_monitoring` | Direct |
| 〃 | 〃 | `compliance.security_scanning_enabled` | (no direct suite field) | Report as unmapped evidence |
| `network-security.rego` | `network.security` / `data.network.security.deny` | `network.remote_access`, `network.vpn_enabled` | `vpn_enabled` | Suite network controls are broader; adapter can set `vpn_enabled` |
| 〃 | 〃 | `network.container_network` | (no direct field) | Unmapped; keep in adapter metadata |
| 〃 | 〃 | `network.open_ports` | (evidence) | Unmapped control; useful for drift/reporting |
| `docker-security.rego` | `docker.security` / per-container | `docker[].privileged` | `docker_privileged_disabled` (global assertion) | Derive global: true only if **no** container privileged |
| 〃 | 〃 | memory/health/ports/mounts | `docker_resource_limits`, others | Partial/heuristic; be explicit (do not overclaim) |
| `backup-policy.rego` | `backup.policy` / `data.backup.policy.deny` | `backup.encrypted` | `backup_encryption_enabled` | Direct |
| 〃 | 〃 | `backup.retention_days` | `backup_retention_days` | Direct |
| 〃 | 〃 | `backup.offsite_replication` | `backup_offsite_enabled` | Direct |
| 〃 | 〃 | `backup.last_success_age` | (evidence) | Not a suite policy field |
| `kubernetes-admission.rego` + tests/versions | `kubernetes.admission` | K8s AdmissionReview objects | (separate domain) | **Do not merge into `data.security[k].deny` aggregation** by default. Place under `spectre/policies/k8s/` or dedicated package/path with separate evaluation/CI; preserve version metadata.

## 4. Adapter behavior (implemented/target)
`spectre/actions/security/baseline/opa-contract-adapter.py`:
- Input: nested spectre-security `current-infrastructure.json` shape.
- Output: **suite-compatible flat JSON** containing only mappable fields (and optional `_adapter` metadata stripped/ignored by policy evaluation as needed).
- **Fail-closed friendly:** does not invent values for unmapped suite controls; missing fields remain undefined → existing suite deny rules behave as designed.
- Supports `SECURITY_OPA_COMPAT` workflows: evaluate adapted input against `spectre/policies` (canonical) and/or produce a report showing mapped/unmapped controls.

## 5. Migration rules (Option A)
1. Never reduce the empty-input fail-closed deny count below the approved baseline without an explicit, reviewed control change and CI/test update.
2. Port tests as `opa test`/rego tests or adapter-driven checks that target the **canonical contract** (or clearly separated compat namespace).
3. Keep k8s admission/versioned policies isolated until an explicit gate is added.
4. Update `spectre/policies/baseline.json` only when the declared control state changes intentionally.