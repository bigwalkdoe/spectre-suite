package security.intrusion_detection_test

import data.security.intrusion_detection
import rego.v1

test_ids_deny_all_when_empty if {
	count(intrusion_detection.deny) == 5 with input as {}
}

test_ids_deny_intrusion_detection_disabled if {
	"ids: intrusion detection is not enabled" in intrusion_detection.deny with input as {"intrusion_detection_active": false}
}

test_ids_deny_fim_disabled if {
	"ids: file integrity monitoring is not enabled" in intrusion_detection.deny with input as {"file_integrity_monitoring": false}
}

test_ids_deny_fail2ban_not_configured if {
	# fail2ban_configured is a distinct suite control (not asserted from intrusion_detection_active alone).
	"ids: fail2ban is not configured" in intrusion_detection.deny with input as {"fail2ban_configured": false}
}

test_ids_deny_log_monitoring_disabled if {
	"ids: log monitoring is not enabled" in intrusion_detection.deny with input as {"log_monitoring_enabled": false}
}

test_ids_deny_alert_thresholds_missing if {
	"ids: alert thresholds are not configured" in intrusion_detection.deny with input as {"alert_thresholds_configured": false}
}

test_ids_mapped_adapter_fields_leave_distinct_controls_fail_closed if {
	# Nested adapter maps intrusion_detection_active/file_integrity_monitoring; others remain fail-closed.
	msgs := intrusion_detection.deny with input as {
		"intrusion_detection_active": true,
		"file_integrity_monitoring": true,
	}
	not "ids: intrusion detection is not enabled" in msgs
	not "ids: file integrity monitoring is not enabled" in msgs
	count(msgs) == 3
}

test_ids_no_denials_when_baseline_compliant if {
	count(intrusion_detection.deny) == 0 with input as {
		"intrusion_detection_active": true,
		"file_integrity_monitoring": true,
		"fail2ban_configured": true,
		"log_monitoring_enabled": true,
		"alert_thresholds_configured": true,
	}
}
