# Runbooks

- [Security baseline OPA alerts — semantics](security-baseline-opa-alerts.md): distinguishes `OPACheckFailed` (suite check), `OPATestsFailed` (legacy compat tests), and `OPACompatReportIssues` (Option A compat report-ran helper/exec issues; **not policy denials**).
- [Security audit remediation — wildcard listeners + SSH root login](security-audit-remediation.md): privileged commands for the remaining `spectre security --audit` findings (ports + `PermitRootLogin`).
