# Spectre Suite Web Dashboard

A custom web-based monitoring dashboard that provides real-time system metrics and monitoring capabilities.

## Features

### Navigation
- Side panel tabs route to focused pages (Overview, System Health, Alerts, Containers, Trends, Security, Backup)
- The sidebar and main content scroll independently; the top bar stays sticky
- All metric cards remain in the DOM so Prometheus-backed updates continue across pages
- Key metric cards and active alerts include drill-down links to Prometheus/Alertmanager/Grafana (and alert `generatorURL` when provided) for faster investigation
- Container names (when available) link to Prometheus container CPU drill-down queries; chart drill-downs open in Prometheus/Grafana for deeper analysis
- Active alerts can open in-context runbooks served from `/runbooks/<AlertName>.md` (with safe plain-text rendering and fallback guidance when missing)

### Real-time Metrics
- **CPU Usage**: Live CPU utilization with status indicators
- **Memory Usage**: Memory consumption tracking
- **Disk Usage**: Storage monitoring with alerts
- **Network I/O**: Real-time network traffic monitoring
- **Resource Trends:** time-range presets (1h/6h/24h/7d) backed by Prometheus `query_range`, persisted in-browser and used for trend chart refreshes

### System Health
- System load monitoring
- Uptime tracking
- Process count
- Temperature monitoring

### Alert Management
- Active alerts display
- Alert severity classification
- Real-time alert updates from Prometheus

### Container Monitoring
- Docker container status
- Container health checks
- Resource usage per container

### Quick Actions
- One-click backup initiation
- System maintenance triggers
- Security scan execution
- Log viewing

### Security Status
- Firewall status monitoring
- Fail2Ban status
- Last security scan time
- Vulnerability count

## Deployment

### Prerequisites
- Docker and Docker Compose
- Running monitoring stack (Prometheus, Grafana)

### Deployment Steps

1. **Deploy Monitoring Stack** (if not already deployed):
   ```bash
   spectre run deploy-monitoring
   ```

2. **Access the Dashboard**:
   - Open http://localhost:20160 in your browser

### Manual Deployment

If you prefer manual deployment:

```bash
cd /path/to/spectre-suite
docker-compose -f docker-compose.monitoring.yml up -d web-dashboard
```

## Architecture

### Components
- **Frontend**: HTML5, CSS3, JavaScript
- **Web Server**: Nginx (Alpine)
- **Data Source**: Prometheus API
- **Integration**: Direct connection to Prometheus metrics

### Data Flow
```
Web Dashboard → Prometheus API → System Metrics
                ↓
            Real-time Updates
```

## Configuration

### Prometheus Connection
The dashboard is served by nginx and proxies Prometheus at same-origin `/api/` (see `web-dashboard/nginx.conf`). Default in-browser config is set in `web-dashboard/js/config.js`:

```javascript
// web-dashboard/js/config.js
export const PROMETHEUS_URL = '/api';
```

To point at a different proxied path/backend, update `PROMETHEUS_URL` in `web-dashboard/js/config.js` (and nginx proxy config as needed).

### Refresh Interval
Default dashboard refresh interval is 30 seconds and can be overridden via URL params/config in `web-dashboard/js/config.js` (e.g. `DEFAULT_REFRESH_INTERVAL`). Chart/report query ranges use the dashboard's selected time range controls.

### Quick Actions & Action Endpoints
Quick actions (`Run Backup`, `Run Maintenance`, `Security Scan`) post to `/actions/<action>` via the nginx proxy to the `dashboard-actions` service.

- The action service is **allowlisted** and **token-protected**. It queues trigger files; a host handler runs the scripts.
- Set `DASHBOARD_ACTION_TOKEN` in `.env`.
- Install the host handler: `./spectre/actions/systemd/install-dashboard-actions-handler.sh` (or copy units from `systemd/dashboard-actions/` and adjust paths).
- Trigger actions with the dashboard; when prompted, enter the token (stored in `sessionStorage` for the browser session).
- The host trigger handler records bounded, redacted run status/result artifacts under `dashboard-actions/triggers/runs/<trigger-id>.json` (queued/running/succeeded/failed/rejected with timestamps, exit code, and safe message) for audit/status consumption.
- Read-only, token-protected run status endpoints are proxied via nginx: `GET /actions/runs?limit=&status=` and `GET /actions/runs/<id>` (same `X-Dashboard-Action-Token` auth requirements as action requests). `GET /actions/healthz` is available for service health. Queueing remains `POST /actions/<action>` only.
- The dashboard includes an **Action Activity** panel (Overview) showing recent queued/running/completed runs, trigger IDs, timestamps, and safe outcomes/messages returned by the runs API. Use the refresh button or wait for periodic updates; provide the action token in-session if required.

To disable actions in the UI: open the dashboard with `?actionsBase=off`.
For safe sharing/view-only access, open with `?readOnly=1` (or `true`): the UI shows a read-only banner and blocks operator actions. `readOnly` takes precedence for UI/action behavior (actions disabled), while `actionsBase=off` also disables action endpoints in the UI. UI read-only mode is not a substitute for server-side auth/restrictions when exposing the dashboard.


## Customization

### Adding Custom Metrics
To add custom metrics to the dashboard (modular frontend):

1. Add query/aggregation logic in `web-dashboard/js/dashboard-core.js` (and `web-dashboard/js/prometheus.js` if a reusable query helper is needed):
```javascript
import { queryPrometheus } from './prometheus.js';

async function queryCustomMetric() {
    return await queryPrometheus('your_prometheus_query');
}
```

2. Update the UI in `index.html`:
```html
<div class="stat-card custom">
    <div class="stat-icon">
        <i class="fas fa-icon"></i>
    </div>
    <div class="stat-content">
        <div class="stat-label">Custom Metric</div>
        <div class="stat-value" id="customValue">--</div>
    </div>
</div>
```

### Styling
Modify `styles.css` to customize:
- Color schemes
- Layout
- Card designs
- Responsive behavior

## Integration

### With Existing Scripts
The dashboard integrates with existing system maintenance scripts:
- Backup scripts
- Maintenance scripts
- Security scanning scripts
- Log monitoring

### API Endpoints (Future)
Planned features include:
- REST API for dashboard actions
- WebSocket for real-time updates
- Authentication and authorization
- Multi-server support

## Security Considerations

### Production Hardening (nginx)
The dashboard nginx config includes baseline hardening: `server_tokens off`, `X-Content-Type-Options`, `X-Frame-Options: SAMEORIGIN`, `Referrer-Policy`, `Permissions-Policy`, `Cross-Origin-Resource-Policy`, and an enforced same-origin `Content-Security-Policy` (Font Awesome is vendored under `vendor/fontawesome/`; no CDN script/style/font dependency). Dotfiles and dashboard internals (`nginx.conf`, `README.md`, `actions-backend/`, `edge-hardening.example.nginx.conf`, `00-http-hardening.conf`) are denied from the bind-mounted document root.

`00-http-hardening.conf` defines http-level request/connection limits; it is mounted into nginx `conf.d` by `docker-compose.monitoring.yml`. `/api/` is limited to `GET|HEAD`; action queueing is `POST /actions/<action>` only while run-status/health reads are `GET|HEAD` on specific `/actions/*` paths, with token checks enforced by the backend when configured. The web-dashboard container runs read-only with tmpfs and `no-new-privileges`.

### Deployment profiles for sharing
- **Viewer (read-only, safest):** expose dashboard over trusted network/VPN or behind SSO, use `?readOnly=1` for operator UI gating, and avoid sharing action tokens. Consider restricting/removing proxied admin UIs (`/prometheus/`, `/grafana/`, `/alertmanager/`) at the edge or in nginx for non-admin users.
- **Operator (actions enabled):** require strong edge authentication/authorization (SSO/MFA), TLS+HSTS, and scoped access to `/actions/`; use `DASHBOARD_ACTION_TOKEN` as a controlled secret, rotate it, and monitor/audit `dashboard-actions` stderr events and nginx logs. Keep the host trigger handler and `dashboard-actions/triggers/` permissions tightly controlled.
- **Restricted proxied UIs:** if sharing broadly, prefer dashboard-only access (`/` + `/api/*`) and do not expose backend UIs through the dashboard proxy; if proxied UIs are needed, gate them behind admin-only auth at the edge/reverse proxy.

### Production Deployment
For production use:
1. Enable authentication (reverse proxy / SSO). See `web-dashboard/edge-hardening.example.nginx.conf` for a TLS/auth edge example.
2. Use HTTPS and add HSTS at the TLS termination layer.
3. Restrict network access (dashboard is published on `127.0.0.1:8081` by default).
4. Keep and tune rate limiting for `/actions/` and API proxy endpoints; add edge/WAF limits before public exposure.
5. Collect audit logs: nginx access logs and `dashboard-actions` JSON stderr audit events (`auth_rejected`, `action_rejected`, `action_queued`, failures). Never log action tokens.
6. Review CSP violations before adding new script/style sources.

### Current Limitations
- No built-in authentication (use reverse proxy)
- HTTP only inside the container (use TLS termination)
- No user management
- Action endpoints are allowlisted/token-protected, but deployment still requires careful host-handler and trigger-directory controls; UI read-only mode is not a server-side authorization boundary.

## Troubleshooting

### Dashboard Not Loading
1. Check if the web-dashboard container is running:
   ```bash
   docker ps | grep web-dashboard
   ```

2. Check container logs:
   ```bash
   docker logs web-dashboard
   ```

### Metrics Not Updating
1. Verify Prometheus connection:
   - Check Prometheus status at http://localhost:20161/prometheus/
   - Verify network connectivity

2. Check browser console for JavaScript errors

3. Verify Prometheus queries are valid in the Prometheus UI

4. Review the **Diagnostics → Data coverage & freshness** panel in the dashboard (including the targets/fleet rollup showing per-job up/down counts):
   - It reports target/exporter presence (`up`), disabled scrape jobs, and common missing-series cases.
   - **Containers:** in this stack, the `cadvisor` Prometheus scrape job is disabled by default (`prometheus/prometheus.yml`) due to prior high CPU usage. The dashboard reports this explicitly. To enable, uncomment/tune the cAdvisor job (e.g. longer scrape/housekeeping intervals) and start/tune the `cadvisor` service in `docker-compose.monitoring.yml`, then restart Prometheus/cAdvisor and re-evaluate host CPU impact.
   - **Disk/filesystem:** disk cards/alerts depend on `node_filesystem_*` for mountpoint `/`. If node-exporter cannot read host mountinfo (e.g. Docker user namespace remapping without `pid: host`, which is incompatible with `userns-remap`), filesystem series may be missing and will be shown as a coverage issue.

### CORS Issues
If you encounter CORS errors when accessing Prometheus:
1. Configure Prometheus to allow CORS
2. Use a reverse proxy
3. Deploy dashboard behind same domain as Prometheus

## Performance

### Optimizations
- Core system metrics refresh on the normal interval; backup/security/baseline
  metrics are cached and refreshed at most every 5 minutes (or immediately on a
  manual refresh)
- Chart history is refreshed on load, manual refresh, range changes, or every
  5 minutes during auto-refresh instead of on every polling tick
- Chart history resolution is capped at roughly 400 points per series
- Prometheus requests time out after 12-20 seconds so a stalled backend cannot
  block the whole dashboard
- Container list DOM is only rebuilt when the container set changes
- Auto-refresh and the live clock pause while the browser tab is hidden
- nginx gzip compression for static assets and proxied JSON responses

### Scalability
- Supports multiple servers with proper Prometheus configuration
- Can handle hundreds of metrics
- Efficient rendering for real-time updates

## Future Enhancements

- [ ] User authentication
- [ ] Multi-server support
- [ ] Historical data visualization
- [ ] Custom dashboard builder
- [ ] Mobile application
- [ ] Export functionality
- [ ] Advanced alerting
- [ ] Integration with incident management

## Support

For issues or questions:
1. Check the main project documentation
2. Review Prometheus documentation
3. Check container logs
4. Open an issue on GitHub

## License

Same as the main project (MIT License)
