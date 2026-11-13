# Dashboard Actions Backend (4b)

Minimal, **allowlisted**, token-protected trigger service for the web dashboard quick actions.

## Security model

- **Allowlist only**: maps action names to fixed repo-relative canonical action scripts. No user-supplied arguments are passed to the shell.
  - `backup` → `spectre/actions/backups/run-missed-backups.sh` (`spectre run backups/run-missed-backups`)
  - `maintenance` → `spectre/actions/maintenance/run-maintenance.sh` (`spectre run maintenance/run-maintenance`)
  - `security-scan` → `spectre/actions/security/scan-docker-images.sh` (`spectre run security/scan-docker-images`)
- **Token required**: when `DASHBOARD_ACTION_TOKEN` is set, requests must include `X-Dashboard-Action-Token`. If unset, the service rejects all action requests (`503`).
- **No in-container execution**: the container **queues trigger files** to `/triggers` and returns `202 Accepted`. A **host handler** runs the allowlisted scripts. This avoids granting the container docker/host/root privileges.

## Components

- `web-dashboard/actions-backend/server.py` — stdlib Python HTTP service (`/healthz`, `POST /<action>`).
- `docker-compose.monitoring.yml` service `dashboard-actions` — builds the backend, mounts `./dashboard-actions/triggers` and the repo read-only.
- `web-dashboard/nginx.conf` — proxies `/actions/` → `dashboard-actions:8090`.
- `web-dashboard/dashboard.js` — posts to `/actions/<name>` (configurable via `?actionsBase=`; `actionsBase=off` disables), prompts/stores token in `sessionStorage` on `401`.
- Host handler: `spectre/actions/dashboard-actions/process-triggers.sh` (or `spectre run dashboard-actions/process-triggers`) consumes queued triggers.
- Systemd templates: `systemd/dashboard-actions/spectre-dashboard-actions.{path,service}` (user units, adjust repo path if needed).

## Setup

1. Set a token in `.env`:
   ```bash
   # generate a token, then set DASHBOARD_ACTION_TOKEN in .env
   python3 -c 'import secrets; print(secrets.token_urlsafe(32))'
   ```
2. Start/rebuild the monitoring stack (includes `dashboard-actions`):
   ```bash
   docker compose -f docker-compose.monitoring.yml up -d --build dashboard-actions web-dashboard
   ```
3. Install the **host trigger handler** (required for actions to actually execute). The provided systemd units are templates under `systemd/dashboard-actions/` and assume the repo at `%h/dev/github/spectre-suite` — copy/edit paths if different:
   ```bash
   mkdir -p ~/.config/systemd/user
   cp systemd/dashboard-actions/spectre-dashboard-actions.{path,service} ~/.config/systemd/user/
   systemctl --user daemon-reload
   systemctl --user enable --now spectre-dashboard-actions.path
   ```
4. In the dashboard, trigger an action; if prompted, enter `DASHBOARD_ACTION_TOKEN` (stored for the browser session).

## Operational notes

- Trigger files: `dashboard-actions/triggers/*.json` → moved to `processed/` or `failed/` by the host handler. Runtime contents are gitignored.
- The container makes `/triggers` sticky world-writable (`1777`, `/tmp` model) at startup so the unprivileged server user can create trigger files while the host handler (directory owner) can move them. This is required because the bind mount is owned by the host operator. Do not mount `/triggers` over a directory that must stay mode 755.
- Scripts may require root/sudo, docker access, or host paths (`/backups`). Review/adjust the allowlisted scripts and the handler's execution context for your host.
- The dashboard itself remains unauthenticated and localhost-bound by default; treat the action token as sensitive.
- To disable actions in the UI: open with `?actionsBase=off`.
