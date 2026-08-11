package security.docker

# Docker must not run as root
docker_not_root = true

rule if {
    input.docker_not_root == true
}

# Docker must have no-new-privileges
docker_no_new_privileges = true

rule if {
    input.docker_no_new_privileges == true
}

# Docker must have userland-proxy disabled
docker_userland_proxy_disabled = true

rule if {
    input.docker_userland_proxy_disabled == true
}

# Containers must have resource limits
docker_resource_limits = true

rule if {
    input.docker_resource_limits == true
}

# Privileged containers must be disabled
docker_privileged_disabled = true

rule if {
    input.docker_privileged_disabled == true
}