package security.intrusion_detection

# Intrusion detection must be enabled
intrusion_detection_active = true

rule {
    input.intrusion_detection_active == true
}

# File integrity monitoring must be enabled
file_integrity_monitoring = true

rule {
    input.file_integrity_monitoring == true
}

# Fail2Ban must be configured
fail2ban_configured = true

rule {
    input.fail2ban_configured == true
}

# Log monitoring must be enabled
log_monitoring_enabled = true

rule {
    input.log_monitoring_enabled == true
}

# Alert thresholds must be reasonable
alert_thresholds_configured = true

rule {
    input.alert_thresholds_configured == true
}