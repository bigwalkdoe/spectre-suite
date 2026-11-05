# Implementation Plan (2026-11-05)

Implement in order:

1. **Reconcile Alertmanager templates** - consolidate duplicate, wire templates into Alertmanager+Compose (Slack-only), update deploy script.
2. **Align deploy-enhanced-monitoring.sh** - make idempotent/consistent with current stack (pinned images, no blind appends that conflict).
3. **Documentation truth pass** - verify AIDE/check-file-integrity and schedule claims; fix README inconsistencies.
4. **Operational verification** - run config checks/tests possible in this environment; document host-only steps.
5. **CI/tests hygiene** - run relevant local tests; note workflow alignment findings.

## Progress
- [x] 1 Reconciled Alertmanager templates (Slack-only canonical in `prometheus/templates/`, wired via config+compose), removed root duplicate.
- [x] 2 Rewrote `scripts/deploy-enhanced-monitoring.sh` as non-destructive alignment checker.
- [ ] 3
- [ ] 4
- [ ] 5
