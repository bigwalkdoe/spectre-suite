package security.firewall_test

import data.security.firewall
import rego.v1

test_firewall_deny_all_when_empty if {
	count(firewall.deny) == 4 with input as {}
}

test_firewall_deny_inactive if {
	"firewall: firewalld is not active" in firewall.deny with input as {"firewall_enabled": false}
}

test_firewall_deny_ssh_password_auth_enabled if {
	"firewall: SSH password authentication is enabled" in firewall.deny with input as {"ssh_password_auth": true}
}

test_firewall_deny_ssh_root_login_enabled if {
	"firewall: SSH root login is enabled" in firewall.deny with input as {"ssh_root_login": true}
}

test_firewall_deny_fail2ban_inactive if {
	"firewall: fail2ban is not active" in firewall.deny with input as {"fail2ban_active": false}
}

test_firewall_no_denials_when_baseline_compliant if {
	count(firewall.deny) == 0 with input as {
		"firewall_enabled": true,
		"ssh_password_auth": false,
		"ssh_root_login": false,
		"fail2ban_active": true,
	}
}
