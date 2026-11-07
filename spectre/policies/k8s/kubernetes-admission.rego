package kubernetes.admission

import rego.v1

# Kubernetes Admission Controller Policies
# Enforced via OPA Gatekeeper or Kyverno.
#
# ISOLATED DOMAIN: this package is NOT part of the suite's
# data.security[k].deny aggregation and does not change core CI gates.
# Vendored from spectre-security (v0.1.0) as an isolated report slice.

# 1. Disallow privileged containers
deny contains msg if {
	input.request.object.spec.containers[_].securityContext.privileged == true
	msg := "Privileged containers are not allowed"
}

deny contains msg if {
	input.request.object.spec.initContainers[_].securityContext.privileged == true
	msg := "Privileged init containers are not allowed"
}

# 2. Require non-root user
deny contains msg if {
	container := input.request.object.spec.containers[_]
	not container.securityContext.runAsNonRoot
	not container.securityContext.runAsUser
	msg := sprintf("Container %s must run as non-root user", [container.name])
}

deny contains msg if {
	container := input.request.object.spec.initContainers[_]
	not container.securityContext.runAsNonRoot
	not container.securityContext.runAsUser
	msg := sprintf("Init container %s must run as non-root user", [container.name])
}

# 3. Disallow host namespace sharing
deny contains msg if {
	input.request.object.spec.hostNetwork == true
	msg := "Host network namespace sharing is not allowed"
}

deny contains msg if {
	input.request.object.spec.hostPID == true
	msg := "Host PID namespace sharing is not allowed"
}

deny contains msg if {
	input.request.object.spec.hostIPC == true
	msg := "Host IPC namespace sharing is not allowed"
}

# 4. Require resource limits
deny contains msg if {
	container := input.request.object.spec.containers[_]
	not container.resources.limits.memory
	msg := sprintf("Container %s must have memory limit", [container.name])
}

deny contains msg if {
	container := input.request.object.spec.containers[_]
	not container.resources.limits.cpu
	msg := sprintf("Container %s must have CPU limit", [container.name])
}

deny contains msg if {
	container := input.request.object.spec.containers[_]
	not container.resources.requests.memory
	msg := sprintf("Container %s must have memory request", [container.name])
}

deny contains msg if {
	container := input.request.object.spec.containers[_]
	not container.resources.requests.cpu
	msg := sprintf("Container %s must have CPU request", [container.name])
}

# 5. Disallow dangerous capabilities
dangerous_caps := {"SYS_ADMIN", "SYS_MODULE", "SYS_RAWIO", "SYS_PTRACE", "SYS_RESOURCE", "DAC_OVERRIDE", "DAC_READ_SEARCH"}

deny contains msg if {
	cap := input.request.object.spec.containers[_].securityContext.capabilities.add[_]
	dangerous_caps[cap]
	msg := sprintf("Dangerous capability %s not allowed", [cap])
}

# 6. Require read-only root filesystem
deny contains msg if {
	container := input.request.object.spec.containers[_]
	container.securityContext.readOnlyRootFilesystem != true
	msg := sprintf("Container %s must have readOnlyRootFilesystem=true", [container.name])
}

# 7. Require liveness and readiness probes
deny contains msg if {
	container := input.request.object.spec.containers[_]
	not container.livenessProbe
	msg := sprintf("Container %s must have liveness probe", [container.name])
}

deny contains msg if {
	container := input.request.object.spec.containers[_]
	not container.readinessProbe
	msg := sprintf("Container %s must have readiness probe", [container.name])
}

# 8. Disallow hostPath volumes (except allowed paths)
deny contains msg if {
	volume := input.request.object.spec.volumes[_]
	volume.hostPath
	not allowed_host_path(volume.hostPath.path)
	msg := sprintf("HostPath volume %s not allowed", [volume.hostPath.path])
}

allowed_host_path(path) if {
	allowed := {"/var/log", "/var/lib/kubelet", "/etc/kubernetes"}
	allowed[path]
}

# 9. Require pod security standards labels
deny contains msg if {
	not input.request.object.metadata.labels["pod-security.kubernetes.io/enforce"]
	msg := "Pod must have pod-security.kubernetes.io/enforce label"
}

# 10. Disallow hostPort
deny contains msg if {
	port := input.request.object.spec.containers[_].ports[_]
	port.hostPort
	msg := sprintf("hostPort %d not allowed", [port.hostPort])
}
