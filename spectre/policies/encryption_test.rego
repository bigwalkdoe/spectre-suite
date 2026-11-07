package security.encryption_test

import data.security.encryption
import rego.v1

test_encryption_deny_all_when_empty if {
	count(encryption.deny) == 5 with input as {}
}

test_encryption_deny_at_rest_disabled if {
	"encryption: encryption at rest is not enabled" in encryption.deny with input as {"encryption_at_rest_enabled": false}
}

test_encryption_deny_in_transit_disabled if {
	"encryption: encryption in transit is not enabled" in encryption.deny with input as {"encryption_in_transit_enabled": false}
}

test_encryption_deny_tls_missing if {
	"encryption: TLS is not configured for all services" in encryption.deny with input as {"tls_configured": false}
}

test_encryption_deny_cert_monitoring_disabled if {
	"encryption: certificate expiry is not monitored" in encryption.deny with input as {"certificate_monitoring_enabled": false}
}

test_encryption_deny_key_rotation_disabled if {
	"encryption: key rotation is not performed" in encryption.deny with input as {"key_rotation_enabled": false}
}

test_encryption_no_denials_when_baseline_compliant if {
	count(encryption.deny) == 0 with input as {
		"encryption_at_rest_enabled": true,
		"encryption_in_transit_enabled": true,
		"tls_configured": true,
		"certificate_monitoring_enabled": true,
		"key_rotation_enabled": true,
	}
}
