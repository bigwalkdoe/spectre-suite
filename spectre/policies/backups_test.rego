package security.backups_test

import data.security.backups
import rego.v1

# Canonical suite contract: fail-closed on missing/false controls.

test_backups_deny_all_when_empty if {
	count(backups.deny) == 6 with input as {}
}

test_backups_deny_encryption_missing if {
	"backups: encryption at rest is not enabled" in backups.deny with input as {"backup_encryption_enabled": false}
}

test_backups_deny_retention_under_7 if {
	"backups: retention is under 7 days" in backups.deny with input as {"backup_retention_days": 6}
}

test_backups_deny_offsite_missing if {
	"backups: off-site replication is not enabled" in backups.deny with input as {"backup_offsite_enabled": false}
}

test_backups_deny_verification_missing if {
	"backups: restore verification is not enabled" in backups.deny with input as {"backup_verification_enabled": false}
}

test_backups_deny_database_backups_missing if {
	"backups: databases are not included" in backups.deny with input as {"database_backups_enabled": false}
}

test_backups_deny_docker_volume_backups_missing if {
	"backups: docker volumes are not included" in backups.deny with input as {"docker_volume_backups_enabled": false}
}

test_backups_allow_mapped_controls_when_set if {
	# Mapped controls satisfied; unmapped suite-only controls remain fail-closed (3).
	msgs := backups.deny with input as {
		"backup_encryption_enabled": true,
		"backup_retention_days": 30,
		"backup_offsite_enabled": true,
	}
	not "backups: encryption at rest is not enabled" in msgs
	not "backups: retention is under 7 days" in msgs
	not "backups: off-site replication is not enabled" in msgs
	count(msgs) == 3
}

test_backups_no_denials_when_baseline_compliant if {
	count(backups.deny) == 0 with input as {
		"backup_encryption_enabled": true,
		"backup_retention_days": 7,
		"backup_offsite_enabled": true,
		"backup_verification_enabled": true,
		"database_backups_enabled": true,
		"docker_volume_backups_enabled": true,
	}
}
