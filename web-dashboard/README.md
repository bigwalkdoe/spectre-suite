# System Maintenance Web Dashboard

A custom web-based monitoring dashboard that provides real-time system metrics and monitoring capabilities.

## Features

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
   ./scripts/deploy-monitoring.sh
   ```

2. **Access the Dashboard**:
   - Open http://localhost:8081 in your browser

### Manual Deployment

If you prefer manual deployment:

```bash
cd /path/to/system-maintenance
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

### Production Deployment
For production use:
1. Enable authentication
2. Use HTTPS
3. Restrict network access
4. Implement rate limiting
5. Add audit logging

### Current Limitations
- No authentication (use reverse proxy)
- HTTP only (use SSL termination)
- No user management

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
- Efficient Prometheus queries
- Minimal data transfer
- Client-side caching
- Lazy loading for charts

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
