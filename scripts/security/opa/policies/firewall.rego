package security.firewall

# Firewall must be enabled
firewall_enabled = true

rule if {
    input.firewall_enabled == true
}

# SSH password authentication must be disabled
ssh_password_auth_disabled = true

rule if {
    input.ssh_password_auth == false
}

# Root login via SSH must be disabled
ssh_root_login_disabled = true

rule if {
    input.ssh_root_login == false
}

# Fail2Ban must be active
fail2ban_active = true

rule if {
    input.fail2ban_active == true
}