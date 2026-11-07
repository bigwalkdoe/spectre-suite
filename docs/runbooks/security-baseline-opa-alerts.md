# Security baseline OPA alerts — semantics

- **SecurityBaselineOPACheckFailed** (`spectre_security_baseline_opa_check_ok == 0`): suite-native `opa check` reported issues. Review OPA check logs/evidence.
- **SecurityBaselineOPATestsFailed** (`spectre_security_baseline_opa_tests_ok == 0`): legacy compat policy tests failed (actual test/contract failures). Treat as policy/contract drift; review compat test logs. `-1` = unknown/skipped (no alert).
- **SecurityBaselineOPACompatReportIssues** (`spectre_security_baseline_opa_compat_report_ok == 0`): Option A compat report (`SECURITY_OPA_COMPAT`) had **helper/exec issues only**. **Report-ran semantics (NOT “no denials”):** `1` = report produced/ran (policy denials do **not** make this 0), `0` = issues, `-1` = off/unknown/skipped (no alert). Review `opa-compat-report.log` / baseline evidence. Distinct from check/tests and from policy denials.
