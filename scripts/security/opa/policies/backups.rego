package security.backups

# Backup encryption must be enabled
backup_encryption_enabled = true

rule {
    input.backup_encryption_enabled == true
}

# Backup retention must meet minimum period
backup_retention_days >= 7

rule {
    input.backup_retention_days >= 7
}

# Off-site replication must be enabled
backup_offsite_enabled = true

rule {
    input.backup_offsite_enabled == true
}

# Backup verification must be performed
backup_verification_enabled = true

rule {
    input.backup_verification_enabled == true
}

# Database backups must be included
database_backups_enabled = true

rule {
    input.database_backups_enabled == true
}

# Docker volume backups must be included
docker_volume_backups_enabled = true

rule {
    input.docker_volume_backups_enabled == true
}