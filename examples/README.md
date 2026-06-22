# Examples Directory

This directory contains configuration examples and sample configurations for the System Maintenance Suite.

## Available Examples

### Backup Configurations
- `backup-config-example.yml` - Example backup configuration
- `retention-policies.yml` - Different retention policy examples

### Monitoring Configurations
- `prometheus-alerts-example.yml` - Example Prometheus alert rules
- `grafana-dashboard-example.json` - Example Grafana dashboard
- `alertmanager-config-example.yml` - Example Alertmanager configuration

### Security Configurations
- `fail2ban-jails-example.conf` - Example Fail2Ban jail configurations
- `firewall-rules-example.sh` - Example firewall rules
- `docker-security-example.json` - Example Docker security configuration

### System Configurations
- `systemd-timers-example/` - Example systemd timer configurations
- `network-config-example.sh` - Example network configuration
- `performance-tuning-example.conf` - Example performance tuning

### Cloud Deployment Examples
- `terraform-aws-example.tf` - Example AWS Terraform configuration
- `ansible-inventory-example.yml` - Example Ansible inventory
- `cloud-init-example.yml` - Example cloud-init configuration

### ML Anomaly Detection Examples
- `ml-config-example.yml` - Example ML configuration
- `training-data-example.csv` - Example training data format
- `alert-rules-example.yml` - Example ML alert rules

## Usage

### Using Backup Configuration Example
```bash
cp examples/backup-config-example.yml /etc/system-maintenance/backup-config.yml
# Edit the configuration as needed
nano /etc/system-maintenance/backup-config.yml
```

### Using Monitoring Configuration Example
```bash
cp examples/prometheus-alerts-example.yml prometheus/alert_rules.yml
# Reload Prometheus
curl -X POST http://localhost:9090/-/reload
```

### Using Security Configuration Example
```bash
cp examples/fail2ban-jails-example.conf /etc/fail2ban/jail.local
# Reload Fail2Ban
sudo systemctl restart fail2ban
```

### Using Cloud Deployment Example
```bash
cd cloud-deployment/terraform
cp ../../examples/terraform-aws-example.tf main.tf
# Modify as needed
terraform apply
```

## Customization

Each example file is designed to be a starting point. Customize them based on your specific requirements:

1. **Review**: Understand the configuration options
2. **Copy**: Copy the example to the appropriate location
3. **Modify**: Adjust settings for your environment
4. **Test**: Test the configuration in a non-production environment
5. **Deploy**: Deploy to production after validation

## Best Practices

1. **Version Control**: Keep custom configurations in version control
2. **Documentation**: Document any custom changes
3. **Testing**: Test all configuration changes thoroughly
4. **Backup**: Backup working configurations before making changes
5. **Validation**: Validate configurations before deployment

## Support

For questions about specific examples:
- Refer to the main documentation
- Check inline comments in example files
- Open an issue on GitHub for clarification
