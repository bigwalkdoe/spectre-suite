# dashboard-actions backend

Minimal allowlisted dashboard action trigger service.

- **POST `/<action>`**: queues an allowlisted action (`backup`, `maintenance`, `security-scan`) by writing a JSON trigger file into `TRIGGERS_DIR` for a host handler. Requires `X-Dashboard-Action-Token` when `DASHBOARD_ACTION_TOKEN` is set (otherwise requests are rejected with 503). Never executes scripts in-container.
- **GET `/healthz`**: health/status and allowlist.
- **GET `/runs` / `/runs/<id>`**: read-only, authenticated access to bounded run status records written by the host handler under `TRIGGERS_DIR/runs/` (when implemented/available).

Security model: allowlist-only actions, token-protected access, no arbitrary shell args, no script execution inside the container, and no logging of tokens/request bodies. Run/status messages are bounded and redacted by the host handler.
