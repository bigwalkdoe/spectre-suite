package security.compliance_test

import data.security.compliance
import rego.v1

# Suite compliance controls are distinct from legacy spectre-security compliance
# semantics (not 1:1); nested adapter must not invent these fields.

test_compliance_deny_all_when_empty if {
	count(compliance.deny) == 5 with input as {}
}

test_compliance_deny_baseline_not_compliant if {
	"compliance: system is not compliant with the security baseline" in compliance.deny with input as {"security_baseline_compliant": false}
}

test_compliance_deny_cis_not_followed if {
	"compliance: CIS benchmarks are not being followed" in compliance.deny with input as {"cis_benchmarks_followed": false}
}

test_compliance_deny_pci_not_met if {
	"compliance: PCI-DSS requirements are not met" in compliance.deny with input as {"pci_dss_compliant": false}
}

test_compliance_deny_assessments_not_scheduled if {
	"compliance: security assessments are not scheduled" in compliance.deny with input as {"security_assessments_scheduled": false}
}

test_compliance_deny_patch_management_inactive if {
	"compliance: patch management is not active" in compliance.deny with input as {"patch_management_active": false}
}

test_compliance_no_denials_when_baseline_compliant if {
	count(compliance.deny) == 0 with input as {
		"security_baseline_compliant": true,
		"cis_benchmarks_followed": true,
		"pci_dss_compliant": true,
		"security_assessments_scheduled": true,
		"patch_management_active": true,
	}
}
