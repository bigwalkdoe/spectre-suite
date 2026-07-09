package security.audit

# Audit logging must be enabled
audit_logging_enabled = true

rule {
    input.audit_logging_enabled == true
}

# Audit logs must be retained for minimum period
audit_retention_days >= 90

rule {
    input.audit_retention_days >= 90
}

# Sudo logging must be enabled
sudo_logging_enabled = true

rule {
    input.sudo_logging_enabled == true
}