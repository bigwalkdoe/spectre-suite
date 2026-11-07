package security.audit_test

import data.security.audit
import rego.v1

test_audit_deny_all_when_empty if {
	count(audit.deny) == 3 with input as {}
}

test_audit_deny_logging_disabled if {
	"audit: auditd/audit logging is not enabled" in audit.deny with input as {"audit_logging_enabled": false}
}

test_audit_deny_retention_under_90 if {
	"audit: audit log retention is under 90 days" in audit.deny with input as {"audit_retention_days": 89}
}

test_audit_deny_sudo_logging_disabled if {
	"audit: sudo logging is not enabled" in audit.deny with input as {"sudo_logging_enabled": false}
}

test_audit_no_denials_when_baseline_compliant if {
	count(audit.deny) == 0 with input as {
		"audit_logging_enabled": true,
		"audit_retention_days": 90,
		"sudo_logging_enabled": true,
	}
}
