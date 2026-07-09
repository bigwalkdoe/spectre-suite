package security.network

# Network segmentation must be enabled
network_segmentation_enabled = true

rule {
    input.network_segmentation_enabled == true
}

# DMZ must be isolated
dmz_isolated = true

rule {
    input.dmz_isolated == true
}

# Internal network must not access internet directly
internal_no_internet = true

rule {
    input.internal_no_internet == true
}

# VPN must be enabled for remote access
vpn_enabled = true

rule {
    input.vpn_enabled == true
}

# DDoS protection must be enabled
ddos_protection_enabled = true

rule {
    input.ddos_protection_enabled == true
}