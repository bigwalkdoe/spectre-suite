package security.network_test

import data.security.network
import rego.v1

test_network_deny_all_when_empty if {
	count(network.deny) == 5 with input as {}
}

test_network_deny_vpn_missing if {
	"network: no VPN is configured for remote access" in network.deny with input as {"vpn_enabled": false}
}

test_network_allow_vpn_when_mapped_other_fail_closed if {
	# vpn_enabled maps from nested adapter; 4 suite-only controls remain fail-closed.
	msgs := network.deny with input as {"vpn_enabled": true}
	not "network: no VPN is configured for remote access" in msgs
	count(msgs) == 4
}

test_network_no_denials_when_baseline_compliant if {
	count(network.deny) == 0 with input as {
		"network_segmentation_enabled": true,
		"dmz_isolated": true,
		"internal_no_internet": true,
		"vpn_enabled": true,
		"ddos_protection_enabled": true,
	}
}
