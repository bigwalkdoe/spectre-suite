package security.compliance

# System must comply with security baseline
security_baseline_compliant = true

rule if {
    input.security_baseline_compliant == true
}

# CIS benchmarks must be followed
cis_benchmarks_followed = true

rule if {
    input.cis_benchmarks_followed == true
}

# PCI-DSS requirements must be met (if applicable)
pci_dss_compliant = true

rule if {
    input.pci_dss_compliant == true
}

# Regular security assessments must be performed
security_assessments_scheduled = true

rule if {
    input.security_assessments_scheduled == true
}

# Patch management must be active
patch_management_active = true

rule if {
    input.patch_management_active == true
}