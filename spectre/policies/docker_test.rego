package security.docker_test

import data.security.docker
import rego.v1

test_docker_deny_all_when_empty if {
	count(docker.deny) == 5 with input as {}
}

test_docker_deny_privileged_enabled if {
	"docker: privileged containers are enabled" in docker.deny with input as {"docker_privileged_disabled": false}
}

test_docker_deny_no_resource_limits if {
	"docker: containers have no resource limits" in docker.deny with input as {"docker_resource_limits": false}
}

test_docker_allow_derived_controls_when_set if {
	# Adapter-derived globals satisfied; 3 unmapped global controls remain fail-closed.
	msgs := docker.deny with input as {"docker_privileged_disabled": true, "docker_resource_limits": true}
	not "docker: privileged containers are enabled" in msgs
	not "docker: containers have no resource limits" in msgs
	count(msgs) == 3
}

test_docker_no_denials_when_baseline_compliant if {
	count(docker.deny) == 0 with input as {
		"docker_not_root": true,
		"docker_no_new_privileges": true,
		"docker_userland_proxy_disabled": true,
		"docker_resource_limits": true,
		"docker_privileged_disabled": true,
	}
}
