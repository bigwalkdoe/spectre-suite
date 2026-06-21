#!/bin/bash
# Network Configuration Optimization Script

echo "Optimizing network configuration..."

# Set up optimized DNS settings
echo "Configuring optimized DNS settings..."

# Backup current NetworkManager configuration
sudo cp /etc/NetworkManager/NetworkManager.conf /etc/NetworkManager/NetworkManager.conf.backup

# Enable DNS caching and set fast DNS servers
sudo bash -c 'cat > /etc/NetworkManager/conf.d/dns.conf << "EOF"
[main]
dns=dnsmasq
rc-manager=symlink
EOF'

# Set up systemd-resolved for better DNS resolution
sudo systemctl enable systemd-resolved
sudo systemctl start systemd-resolved

# Create stub resolver configuration
sudo mkdir -p /etc/systemd/resolved.conf.d
sudo bash -c 'cat > /etc/systemd/resolved.conf.d/dns.conf << "EOF"
[Resolve]
DNS=8.8.8.8 8.8.4.4 1.1.1.1 1.0.0.1
FallbackDNS=9.9.9.9 149.112.112.112
Cache=yes
DNSStubListener=yes
EOF'

# Restart NetworkManager to apply DNS changes
sudo systemctl restart NetworkManager

echo "Network configuration optimized!"
echo "DNS caching enabled"
echo "Fast DNS servers configured"
