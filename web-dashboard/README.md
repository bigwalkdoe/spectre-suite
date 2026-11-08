# Spectre Suite Web Dashboard

A custom web-based monitoring dashboard that provides real-time system metrics and monitoring capabilities.

## Features

### Navigation
- Side panel tabs route to focused pages (Overview, System Health, Alerts, Containers, Trends, Security, Backup)
- The sidebar and main content scroll independently; the top bar stays sticky
- All metric cards remain in the DOM so Prometheus-backed updates continue across pages

### Real-time Metrics
- **CPU Usage**: Live CPU utilization with status indicators
- **Memory Usage**: Memory consumption tracking
- **Disk Usage**: Storage monitoring with alerts
- **Network I/O**: Real-time network traffic monitoring

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
   - Open http://localhost:8081 in your browser

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
The dashboard connects to Prometheus at `http://localhost:9090` by default. To change this:

Edit `web-dashboard/dashboard.js`:
```javascript
const PROMETHEUS_URL = 'http://your-prometheus-url:9090';
```

### Refresh Interval
Default refresh interval is 30 seconds. To change:

Edit `web-dashboard/dashboard.js`:
```javascript
const REFRESH_INTERVAL = 30000; // milliseconds
```

### Quick Actions & Action Endpoints
Quick actions (`Run Backup`, `Run Maintenance`, `Security Scan`) post to `/actions/<action>` via the nginx proxy to the `dashboard-actions` service.

- The action service is **allowlisted** and **token-protected**. It queues trigger files; a host handler runs the scripts.
- Set `DASHBOARD_ACTION_TOKEN` in `.env`.
- Install the host handler: `./spectre/actions/systemd/install-dashboard-actions-handler.sh` (or copy units from `systemd/dashboard-actions/` and adjust paths).
- Trigger actions with the dashboard; when prompted, enter the token (stored in `sessionStorage` for the browser session).

To disable actions in the UI: open the dashboard with `?actionsBase=off`.


## Customization

### Adding Custom Metrics
To add custom metrics to the dashboard:

1. Add a new query function in `dashboard.js`:
```javascript
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
The dashboard nginx config includes baseline hardening: `server_tokens off`, `X-Content-Type-Options`, `X-Frame-Options: SAMEORIGIN`, `Referrer-Policy`, `Permissions-Policy`, `Cross-Origin-Resource-Policy`, and an enforced `Content-Security-Policy` compatible with same-origin dashboard scripts, Font Awesome CDN fonts/styles, and proxied backend frames/connections. Dotfiles and dashboard internals (`nginx.conf`, `README.md`, `actions-backend/`) are denied from the bind-mounted document root.

### Production Deployment
For production use:
1. Enable authentication (reverse proxy / SSO)
2. Use HTTPS and add HSTS at the TLS termination layer
3. Restrict network access (dashboard is published on `127.0.0.1:8081` by default)
4. Add rate limiting for `/actions/` and API proxy endpoints
5. Add audit logging for dashboard actions and access
6. Review CSP reports/violations before adding new script/style sources

### Current Limitations
- No built-in authentication (use reverse proxy)
- HTTP only inside the container (use TLS termination)
- No user management
- Action endpoints are allowlisted/token-protected, but deployment still requires careful host-handler and trigger-directory controls

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
   - Check Prometheus status at http://localhost:9090
   - Verify network connectivity

2. Check browser console for JavaScript errors

3. Verify Prometheus queries are valid in the Prometheus UI

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
