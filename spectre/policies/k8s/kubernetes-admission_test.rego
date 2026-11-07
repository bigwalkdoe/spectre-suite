package kubernetes.admission_test

import data.kubernetes.admission
import rego.v1

# ISOLATED DOMAIN: tests for the vendored k8s admission report slice.
# These do not touch data.security[k].deny or core CI gates.

test_privileged_denied if {
	"Privileged containers are not allowed" in admission.deny with input as {
		"request": {"object": {"spec": {"containers": [{
			"name": "test",
			"securityContext": {"privileged": true},
		}]}}},
	}
}

test_non_root_required if {
	"Container test must run as non-root user" in admission.deny with input as {
		"request": {"object": {"spec": {"containers": [{
			"name": "test",
			"securityContext": {},
		}]}}},
	}
}

test_host_network_denied if {
	"Host network namespace sharing is not allowed" in admission.deny with input as {
		"request": {"object": {"spec": {
			"hostNetwork": true,
			"containers": [{"name": "test"}],
		}}},
	}
}

test_host_pid_denied if {
	"Host PID namespace sharing is not allowed" in admission.deny with input as {
		"request": {"object": {"spec": {
			"hostPID": true,
			"containers": [{"name": "test"}],
		}}},
	}
}

test_host_ipc_denied if {
	"Host IPC namespace sharing is not allowed" in admission.deny with input as {
		"request": {"object": {"spec": {
			"hostIPC": true,
			"containers": [{"name": "test"}],
		}}},
	}
}

test_memory_limit_required if {
	"Container test must have memory limit" in admission.deny with input as {
		"request": {"object": {"spec": {"containers": [{
			"name": "test",
			"resources": {"requests": {"cpu": "100m"}},
		}]}}},
	}
}

test_cpu_limit_required if {
	"Container test must have CPU limit" in admission.deny with input as {
		"request": {"object": {"spec": {"containers": [{
			"name": "test",
			"resources": {"requests": {"memory": "128Mi"}},
		}]}}},
	}
}

test_dangerous_capability_denied if {
	"Dangerous capability SYS_ADMIN not allowed" in admission.deny with input as {
		"request": {"object": {"spec": {"containers": [{
			"name": "test",
			"securityContext": {"capabilities": {"add": ["SYS_ADMIN"]}},
		}]}}},
	}
}

test_readonly_rootfs_required if {
	"Container test must have readOnlyRootFilesystem=true" in admission.deny with input as {
		"request": {"object": {"spec": {"containers": [{
			"name": "test",
			"securityContext": {"readOnlyRootFilesystem": false},
		}]}}},
	}
}

test_liveness_probe_required if {
	"Container test must have liveness probe" in admission.deny with input as {
		"request": {"object": {"spec": {"containers": [{"name": "test"}]}}},
	}
}

test_readiness_probe_required if {
	"Container test must have readiness probe" in admission.deny with input as {
		"request": {"object": {"spec": {"containers": [{"name": "test"}]}}},
	}
}

test_disallowed_hostpath_denied if {
	"HostPath volume /etc not allowed" in admission.deny with input as {
		"request": {"object": {"spec": {
			"volumes": [{"name": "host-volume", "hostPath": {"path": "/etc"}}],
			"containers": [{"name": "test"}],
		}}},
	}
}

test_allowed_hostpath_allowed if {
	count(admission.deny) == 0 with input as {
		"request": {"object": {
			"metadata": {"labels": {"pod-security.kubernetes.io/enforce": "restricted"}},
			"spec": {
				"volumes": [{"name": "log-volume", "hostPath": {"path": "/var/log"}}],
				"containers": [{
					"name": "test",
					"securityContext": {
						"privileged": false,
						"runAsNonRoot": true,
						"runAsUser": 1000,
						"readOnlyRootFilesystem": true,
						"capabilities": {"drop": ["ALL"]},
					},
					"resources": {
						"limits": {"memory": "512Mi", "cpu": "500m"},
						"requests": {"memory": "256Mi", "cpu": "250m"},
					},
					"livenessProbe": {"httpGet": {"path": "/health", "port": 8080}},
					"readinessProbe": {"httpGet": {"path": "/ready", "port": 8080}},
				}],
			},
		}},
	}
}

test_pod_security_label_required if {
	"Pod must have pod-security.kubernetes.io/enforce label" in admission.deny with input as {
		"request": {"object": {
			"metadata": {"labels": {}},
			"spec": {"containers": [{"name": "test"}]},
		}},
	}
}

test_hostport_denied if {
	"hostPort 8080 not allowed" in admission.deny with input as {
		"request": {"object": {"spec": {"containers": [{
			"name": "test",
			"ports": [{"containerPort": 8080, "hostPort": 8080}],
		}]}}},
	}
}

test_compliant_pod if {
	count(admission.deny) == 0 with input as {
		"request": {"object": {
			"metadata": {"labels": {"pod-security.kubernetes.io/enforce": "restricted"}},
			"spec": {"containers": [{
				"name": "test",
				"securityContext": {
					"privileged": false,
					"runAsNonRoot": true,
					"runAsUser": 1000,
					"readOnlyRootFilesystem": true,
					"capabilities": {"drop": ["ALL"]},
				},
				"resources": {
					"limits": {"memory": "512Mi", "cpu": "500m"},
					"requests": {"memory": "256Mi", "cpu": "250m"},
				},
				"livenessProbe": {"httpGet": {"path": "/health", "port": 8080}},
				"readinessProbe": {"httpGet": {"path": "/ready", "port": 8080}},
			}]},
		}},
	}
}
