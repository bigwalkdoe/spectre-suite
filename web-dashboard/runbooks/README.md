# Alert Runbooks

This directory contains operator runbooks mapped by Prometheus `alertname`.

- File name convention: `<AlertName>.md` (exact alert label value, e.g. `HighCPUUsage.md`).
- The dashboard loads these as static files from `/runbooks/<AlertName>.md` and renders them safely as plain text/markdown source for in-context guidance.
- Keep runbooks concise and actionable: meaning, immediate checks, safe mitigations, verification (Prometheus/Grafana/commands), and escalation notes.
- Do not include secrets, credentials, or environment-specific private data.

If no runbook exists for a firing alert, the dashboard shows a "no runbook" state with drill-down links.
