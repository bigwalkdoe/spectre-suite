package security.encryption

# Encryption at rest must be enabled
encryption_at_rest_enabled = true

rule {
    input.encryption_at_rest_enabled == true
}

# Encryption in transit must be enabled
encryption_in_transit_enabled = true

rule {
    input.encryption_in_transit_enabled == true
}

# TLS must be configured for all services
tls_configured = true

rule {
    input.tls_configured == true
}

# Certificate expiration must be monitored
certificate_monitoring_enabled = true

rule {
    input.certificate_monitoring_enabled == true
}

# Key rotation must be performed regularly
key_rotation_enabled = true

rule {
    input.key_rotation_enabled == true
}