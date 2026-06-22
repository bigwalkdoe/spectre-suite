# Multi-Distribution Support

The System Maintenance & Security Automation Suite now supports multiple Linux distributions with automatic detection and distribution-specific optimizations.

## Supported Distributions

### Primary Support
- **Fedora** (tested on Fedora 44+)
- **Ubuntu** (20.04 LTS, 22.04 LTS, 24.04 LTS)
- **Debian** (10+, 11, 12)
- **CentOS** (7, 8, 9 Stream)
- **RHEL** (8, 9)

### Secondary Support
- **Arch Linux**
- **Manjaro**
- **openSUSE Leap**
- **openSUSE Tumbleweed**
- **Rocky Linux**
- **AlmaLinux**
- **Linux Mint**
- **Pop!_OS**

## Distribution Detection

The system automatically detects the Linux distribution using the `/etc/os-release` file or distribution-specific release files.

### Detection Process

1. Check `/etc/os-release` for modern distributions
2. Fallback to `/etc/redhat-release` for RHEL-based systems
3. Fallback to `/etc/debian_version` for Debian-based systems
4. Set appropriate package manager and system commands

### Detection Script

The detection logic is implemented in `scripts/detect-distribution.sh`:

```bash
source scripts/detect-distribution.sh
detect_distribution
set_package_manager
```

## Package Manager Support

### DNF (Fedora, RHEL, CentOS, Rocky, AlmaLinux)
- Package installation: `dnf install -y`
- Package removal: `dnf remove -y`
- System update: `dnf update -y`
- Cache cleaning: `dnf clean all`
- Autoremove: `dnf autoremove -y`

### APT (Ubuntu, Debian, Linux Mint, Pop!_OS)
- Package installation: `apt install -y`
- Package removal: `apt remove -y`
- System update: `apt update && apt upgrade -y`
- Cache cleaning: `apt autoremove -y && apt autoclean`
- Repository management: `/etc/apt/sources.list.d/`

### Pacman (Arch Linux, Manjaro)
- Package installation: `pacman -S --noconfirm`
- Package removal: `pacman -Rns --noconfirm`
- System update: `pacman -Syu --noconfirm`
- Cache cleaning: `pacman -Sc --noconfirm`
- Orphan removal: `pacman -Qtdq | pacman -Rns --noconfirm -`

### Zypper (openSUSE)
- Package installation: `zypper install -y`
- Package removal: `zypper remove -y`
- System update: `zypper dup -y`
- Cache cleaning: `zypper clean`

## Distribution-Specific Features

### Fedora/RHEL/CentOS
- DNF-based package management
- NetworkManager for network configuration
- firewalld for firewall management
- systemd-resolved for DNS

### Ubuntu/Debian
- APT-based package management
- NetworkManager or resolvconf for DNS
- UFW for firewall management
- systemd-resolved for DNS resolution

### Arch Linux
- Pacman-based package management
- NetworkManager for network configuration
- iptables/nftables for firewall
- systemd services

### openSUSE
- Zypper-based package management
- wicked or NetworkManager for networking
- firewalld or SuSEfirewall2

## Script Adaptation

All scripts in the suite have been updated to support multiple distributions:

### Updated Scripts
- `scripts/maintenance/cleanup-system.sh` - Distribution-aware cleanup
- `scripts/security/docker-security-hardening.sh` - Package manager-aware tool installation
- `scripts/network/optimize-network-config.sh` - Distribution-specific network configuration

### Adaptation Pattern

Scripts now follow this pattern:

```bash
#!/bin/bash
# Source distribution detection
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$PROJECT_ROOT/detect-distribution.sh"

# Initialize distribution settings
detect_distribution
set_package_manager
set_distribution_paths

# Use distribution-specific variables
echo "Running on $DISTRO_NAME"
$PKG_INSTALL package-name
$SERVICE_CMD restart service-name
```

## Distribution-Specific Paths

The detection script sets appropriate paths for each distribution:

- `LOG_DIR` - System log directory
- `CACHE_DIR` - Package cache directory
- `TEMP_DIR` - Temporary files directory
- `CONFIG_DIR` - Configuration files directory
- `BACKUP_DIR` - Backup storage directory

## Testing on Different Distributions

### Local Testing
To test on a specific distribution without installing it:

1. Use virtualization (VirtualBox, VMware, libvirt)
2. Use containers (Docker, Podman)
3. Use cloud instances (AWS, DigitalOcean, Linode)

### Docker Testing
```bash
# Test on Ubuntu
docker run -it ubuntu:22.04 bash

# Test on Debian
docker run -it debian:12 bash

# Test on Fedora
docker run -it fedora:latest bash
```

### Virtual Machine Testing
```bash
# Using vagrant
vagrant init ubuntu/focal64
vagrant up
vagrant ssh
```

## Compatibility Notes

### Service Management
All supported distributions use systemd for service management:

```bash
systemctl start service
systemctl stop service
systemctl enable service
systemctl status service
```

### Firewall Management
Different distributions use different firewall tools:

- **Fedora/RHEL**: `firewall-cmd`
- **Ubuntu/Debian**: `ufw`
- **Arch**: `iptables` or `nftables`
- **openSUSE**: `firewall-cmd` or `SuSEfirewall2`

### Network Configuration
All modern distributions use NetworkManager, but some may use alternatives:

- **NetworkManager** (Most common)
- **systemd-networkd** (Arch, some minimal installs)
- **wicked** (openSUSE)
- **netplan** (Ubuntu 18.04+)

## Adding Support for New Distributions

To add support for a new distribution:

1. Update `scripts/detect-distribution.sh`:
   ```bash
   your-distro)
       PKG_MANAGER="package-manager"
       PKG_INSTALL="install-command"
       # ... set other variables
       ;;
   ```

2. Add distribution-specific logic to relevant scripts:
   ```bash
   case "$DISTRO" in
       your-distro)
           # Distribution-specific commands
           ;;
   esac
   ```

3. Test on the actual distribution
4. Update this documentation

## Known Limitations

1. **Package Availability**: Some tools may not be available in all distribution repositories
2. **Version Differences**: Different versions of system tools may behave differently
3. **Configuration Paths**: Some distributions use non-standard configuration paths
4. **Init Systems**: While systemd is standard, some minimal distros use other init systems

## Troubleshooting

### Distribution Not Detected
If your distribution is not detected:
```bash
# Manual detection
cat /etc/os-release
cat /etc/redhat-release
cat /etc/debian_version
```

### Package Manager Not Working
Check if the package manager is installed:
```bash
which dnf
which apt
which pacman
which zypper
```

### Service Commands Failing
Verify systemd is available:
```bash
systemctl --version
```

## Future Enhancements

- [ ] Add support for Alpine Linux
- [ ] Add support for Gentoo
- [ ] Add support for Solus
- [ ] Add support for Void Linux
- [ ] Automated distribution testing
- [ ] Distribution-specific performance optimizations
- [ ] Container-native package management

## Contributing

When adding distribution support:
1. Test on the actual distribution
2. Use the detection script pattern
3. Add distribution-specific logic only when necessary
4. Update this documentation
5. Test with both fresh installations and upgraded systems
