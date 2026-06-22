# Linux System Maintenance & Security Automation

A comprehensive system maintenance and security automation suite for Linux workstations and servers. This project provides automated backups, performance optimization, security hardening, network configuration, and maintenance scheduling with minimal manual intervention required.

## 🚀 Features

- **Automated Backups**: Daily database, Docker volume, configuration, and project backups with retention policies
- **Performance Optimization**: System tuning, Docker resource limits, and performance monitoring
- **Security Hardening**: Vulnerability scanning, Docker security, API protection, automated security updates, IDS/IPS, and advanced threat detection
- **Network Optimization**: DNS caching, network security hardening, and performance tuning
- **Automated Maintenance**: Cleanup scripts, log rotation, health checks, and system maintenance scheduling
- **Comprehensive Monitoring**: Real-time web dashboard, Grafana integration, and comprehensive alerting system

## 📋 Requirements

### Local Installation
- Linux system (Fedora 20+, Ubuntu 20.04+, Debian 10+, CentOS 7+, Arch Linux, and others)
- Docker and Docker Compose
- Systemd (for automated scheduling)
- Bash shell
- Root/sudo access for system-level configurations
- 10GB+ free disk space for backups

### Cloud Deployment
- Terraform >= 1.0 (for infrastructure provisioning)
- Ansible >= 2.9 (for configuration management)
- Cloud provider account (AWS/Azure/GCP)
- SSH access to cloud instances
- Appropriate IAM permissions

### Supported Distributions
- **Primary**: Fedora, Ubuntu, Debian, CentOS, RHEL
- **Secondary**: Arch Linux, Manjaro, openSUSE, Rocky Linux, AlmaLinux, Linux Mint, Pop!_OS

*See [docs/MULTI_DISTRIBUTION_SUPPORT.md](docs/MULTI_DISTRIBUTION_SUPPORT.md) for detailed information.*

## 🔧 Installation

### Quick Start

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/system-maintenance.git
cd system-maintenance

# Run the installation script
sudo ./install.sh

# Verify installation
./scripts/verify-installation.sh
```

### Cloud Deployment

```bash
# Automated cloud deployment (Terraform + Ansible)
cd cloud-deployment

# Deploy to AWS (2 instances, dev environment)
./deploy.sh aws dev 2

# Deploy to staging environment
./deploy.sh aws staging 3

# Deploy to production environment
./deploy.sh aws production 5

# Or use Terraform directly
cd terraform
terraform init
terraform apply

# Then configure with Ansible
cd ../ansible
ansible-playbook -i inventory/production.yml playbook.yml
```

*See [cloud-deployment/docs/CLOUD_DEPLOYMENT_GUIDE.md](cloud-deployment/docs/CLOUD_DEPLOYMENT_GUIDE.md) for detailed cloud deployment instructions.*

### Manual Installation

```bash
# Create required directories
sudo mkdir -p /backups/{databases,docker-volumes,configurations,projects}
sudo chown -R $USER:$USER /backups
chmod -R 755 /backups

# Copy scripts to appropriate locations
sudo cp scripts/*.sh /usr/local/bin/
chmod +x /usr/local/bin/*.sh

# Create systemd timers (requires sudo)
sudo cp systemd/*.service /etc/systemd/system/
sudo cp systemd/*.timer /etc/systemd/system/
sudo systemctl daemon-reload

# Enable timers
sudo systemctl enable backup.timer
sudo systemctl enable maintenance.timer  
sudo systemctl enable performance-check.timer
sudo systemctl enable network-monitor.timer
sudo systemctl enable disk-space-check.timer
sudo systemctl enable security-scan.timer

# Start timers
sudo systemctl start backup.timer
sudo systemctl start maintenance.timer
sudo systemctl start performance-check.timer
sudo systemctl start network-monitor.timer
sudo systemctl start disk-space-check.timer
sudo systemctl start security-scan.timer
```

## 📁 Project Structure

```
system-maintenance/
├── scripts/
│   ├── backups/           # Backup automation scripts
│   ├── performance/       # Performance optimization scripts
│   ├── maintenance/       # System maintenance scripts
│   ├── network/           # Network configuration scripts
│   └── security/          # Security hardening scripts
├── systemd/              # Systemd service and timer definitions
├── docs/                 # Documentation
├── examples/             # Example configurations
├── install.sh           # Installation script
└── README.md             # This file
```

## 🔒 Security Features

### Basic Security
- **SSH Hardening**: Fail2Ban protection, key-based authentication enforcement
- **Docker Security**: Security configurations, resource limits, vulnerability scanning
- **Network Security**: SYN cookies, IP spoofing protection, ICMP controls
- **Application Security**: Dependency vulnerability scanning, API rate limiting
- **Automatic Updates**: Security-only package updates
- **Attack Surface Reduction**: All sensitive services bound to localhost

### Advanced Security
- **Network IDS/IPS**: Suricata-based real-time intrusion detection and prevention
- **Host-based IDS**: OSSEC and AIDE for file integrity monitoring and host intrusion detection
- **Advanced Threat Detection**: Anomaly detection, behavioral analysis, and automated threat response
- **Security Integration**: Unified security framework with comprehensive monitoring and alerting
- **Automated Response**: Multi-level automated incident response capabilities

### ML & AI
- **Anomaly Detection**: Machine learning-based anomaly detection using multiple algorithms
- **Ensemble Methods**: Combines Isolation Forest, One-Class SVM, and statistical analysis
- **Real-time Monitoring**: Continuous ML-based monitoring of system metrics
- **Automated Training**: Scheduled model retraining with fresh data
- **Prometheus Integration**: ML metrics exported for monitoring and alerting

### Testing & CI/CD
- **Automated Testing**: Comprehensive test suite for all components
- **CI/CD Pipeline**: GitHub Actions workflow for continuous integration
- **Multi-environment Testing**: Tests across different Linux distributions
- **Security Scanning**: Automated vulnerability scanning with Trivy
- **Quality Gates**: Automated quality checks and validation

*See [docs/TESTING_AND_CICD.md](docs/TESTING_AND_CICD.md) for detailed information.*

*See [docs/ML_ANOMALY_DETECTION.md](docs/ML_ANOMALY_DETECTION.md) for detailed information.*

*See [docs/ADVANCED_SECURITY_FEATURES.md](docs/ADVANCED_SECURITY_FEATURES.md) for detailed information.*

## 📊 Monitoring & Alerts

- **Disk Space**: Alerts when usage exceeds 80%
- **Performance**: CPU, memory, and performance alerts
- **Security**: Vulnerability scan results and security events
- **System Health**: Comprehensive health checks and reports
- **Backup Status**: Backup completion and failure notifications
- **Network**: Network connectivity and security monitoring

## 📅 Automated Schedules

| Timer | Schedule | Purpose |
|-------|----------|---------|
| backup.timer | Daily at 2 AM | Comprehensive system backups |
| maintenance.timer | Weekly Sundays at 3 AM | System cleanup and maintenance |
| performance-check.timer | Hourly | Performance monitoring |
| network-monitor.timer | Hourly | Network monitoring |
| disk-space-check.timer | Daily at midnight | Disk space monitoring |
| security-scan.timer | Weekly Saturdays at 4 AM | Security vulnerability scanning |
| dnf5-automatic.timer | Daily at 6:17 AM | Security updates |

## 🛠️ Usage

### Manual Backup

```bash
# Run full system backup
sudo /usr/local/bin/backup-all.sh

# Run specific backup type
/usr/local/bin/backup-databases.sh
/usr/local/bin/backup-docker-volumes.sh
/usr/local/bin/backup-configurations.sh
/usr/local/bin/backup-projects.sh
```

### Performance Optimization

```bash
# Run system performance optimization
sudo /usr/local/bin/optimize-system-performance.sh

# Run Docker resource optimization
/usr/local/bin/optimize-docker-resources.sh
```

### Security Scanning

```bash
# Run comprehensive security hardening
/usr/local/bin/run-security-hardening.sh

# Scan dependencies for vulnerabilities
/usr/local/bin/scan-dependencies.sh

# Scan Docker images
/usr/local/bin/scan-docker-images.sh
```

### System Maintenance

```bash
# Run system cleanup and maintenance
/usr/local/bin/run-maintenance.sh

# Run specific maintenance task
/usr/local/bin/cleanup-system.sh
/usr/local/bin/cleanup-logs.sh
/usr/local/bin/system-health-check.sh
```

## 🔧 Configuration

### Backup Configuration

Edit backup scripts to customize:
- Backup directories
- Retention policies
- Backup destinations
- Notification settings

### Performance Configuration

Edit performance scripts to customize:
- Resource thresholds
- Monitoring intervals
- Alert thresholds
- System tuning parameters

### Security Configuration

Edit security scripts to customize:
- Vulnerability scanning tools
- Security policies
- API rate limiting rules
- Monitoring alerts

## 📈 Monitoring Dashboard

The system includes multiple monitoring interfaces:
- **Custom Web Dashboard**: Real-time system metrics and quick actions at `http://localhost:8081`
- **Grafana**: Advanced visualization and dashboards at `http://localhost:3002`
- **Prometheus**: Metrics collection and querying at `http://localhost:9090`
- **Node Exporter**: System metrics exporter
- **Custom Exporters**: Application-specific metrics (Redis, PostgreSQL, Docker)

### Deploying the Monitoring Stack

```bash
# Deploy complete monitoring infrastructure
./scripts/deploy-monitoring.sh

# Or use Docker Compose directly
docker-compose -f docker-compose.monitoring.yml up -d
```

### Access Points
- **Web Dashboard**: http://localhost:8081
- **Grafana**: http://localhost:3002 (admin/changeme - change password on first use)
- **Prometheus**: http://localhost:9090
- **Alertmanager**: http://localhost:9093

## 🐛 Troubleshooting

### Backup Failures

```bash
# Check backup logs
cat /var/log/backup.log

# Check disk space
df -h /backups

# Verify backup timer status
sudo systemctl status backup.timer
```

### Performance Issues

```bash
# Check performance logs
cat /var/log/performance.log

# Check system resources
free -h
top -bn1

# Verify performance timer status
sudo systemctl status performance-check.timer
```

### Security Issues

```bash
# Check security logs
sudo cat /var/log/security-hardening.log

# Check Fail2Ban status
sudo fail2ban-client status

# Verify security scan timer
sudo systemctl status security-scan.timer
```

## 🤝 Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](docs/CONTRIBUTING.md) for details on our code of conduct and the process for submitting pull requests.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Inspired by best practices from Linux system administration
- Security hardening based on CIS Benchmarks
- Docker security recommendations from Docker documentation
- Monitoring tools from Prometheus and Grafana communities

## 📞 Support

For issues, questions, or contributions:
- Open an issue on GitHub
- Check the documentation in the docs/ directory
- Review troubleshooting section above

## 🔮 Future Roadmap

- [x] Web dashboard for system monitoring ✅
- [x] Support for additional Linux distributions ✅
- [ ] Integration with additional monitoring tools
- [x] Advanced security features (IDS/IPS) ✅
- [x] Cloud deployment support ✅
- [ ] Multi-server management
- [x] Machine learning for anomaly detection ✅
- [x] Comprehensive testing and CI/CD pipeline ✅

---

**Note**: This maintenance system is designed for production use but should be tested in a development environment first. Always verify that backups are working correctly before relying on them for production data recovery.
