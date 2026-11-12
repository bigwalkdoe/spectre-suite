# Security audit remediation — wildcard listeners and SSH root login

Privileged runbook for the remaining `spectre security --audit` findings on this host.
Everything here requires root. The secrets-scan false positives are fixed in repo
commit `9a19eea` (see `spectre/agents/security/agent.py` and the test files).

## 1) Wildcard listeners (ports-audit warning)

Observed on this host (2026-11-12): `0.0.0.0` on 22, 80, 5355, 5432, 6379, 15435, 19601.

### 1a) Docker-published ports (no root required to change, but recreate service)

- 15435 -> 5432/tcp (`piis-b02-t4-pg`)
- 19601 -> 3000/tcp (`modelink-workstation-workstation-web-1`)
- 6379 -> 6379/tcp (`compose-redis-1`) if container-published

```bash
# Edit the compose file for the project, change publish to localhost-only:
#   -p 127.0.0.1:15435:5432
#   -p 127.0.0.1:19601:3000
#   -p 127.0.0.1:6379:6379
docker compose up -d <service>
```

### 1b) Host daemons (root)

```bash
# PostgreSQL
sudo -i
# /etc/postgresql/*/main/postgresql.conf
listen_addresses = 'localhost'
# reload: sudo systemctl reload postgresql

# nginx (bind to localhost if only served internally)
# /etc/nginx/sites-enabled/* or conf.d/*
#   listen 80 default_server;   ->   listen 127.0.0.1:80 default_server;
sudo systemctl reload nginx

# LLMNR (if unused)
sudo sed -i 's/^LLMNR=.*/LLMNR=no/' /etc/systemd/resolved.conf
sudo systemctl restart systemd-resolved

# Firewall restrict (example: allow only trusted sources for SSH/HTTP)
sudo firewall-cmd --permanent --add-service=ssh --add-service=http
sudo firewall-cmd --reload
```

Verify: `ss -ltnp`, then `spectre security --audit`.

## 2) SSH root login (ssh-audit warning)

`PermitRootLogin prohibit-password` -> recommend `no`.

```bash
# Precondition: a non-root user with working sudo and SSH access.
sudo -i
# /etc/ssh/sshd_config or /etc/ssh/sshd_config.d/*.conf
sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
# or drop-in: printf 'PermitRootLogin no\n' > /etc/ssh/sshd_config.d/99-no-root.conf
sshd -t && systemctl reload sshd
```

Test in a separate SSH session before closing the current one.