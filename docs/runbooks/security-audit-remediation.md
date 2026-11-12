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

## 3) Per-service hardening checklist (deeper)

For each wildcard listener found here, apply the service-specific hardening that
matches this host’s deployment:

| Port / service | Risk | Remediation checklist |
|---|---|---|
| 22/tcp SSH | Remote admin on wildcard | Firewall allow from trusted sources only; key-based auth only; `PermitRootLogin no`; fail2ban/brute-force monitoring. |
| 80/tcp nginx | Public HTTP | Bind `127.0.0.1:80` (or TLS + reverse proxy); keep firewall allow for intended clients; rate limit; HSTS. |
| 5355/tcp systemd-resolved / LLMNR | Internal name resolution responder | Set `LLMNR=no` in `/etc/systemd/resolved.conf`; restart `systemd-resolved`. |
| 5432/tcp PostgreSQL | DB exposed | `listen_addresses = 'localhost'`; `pg_hba.conf` restrict host access to trusted sources + scram auth + TLS if remote needed; reload. |
| 6379/tcp Redis | Cache/queue exposed | `bind 127.0.0.1`; enable `requirepass`; keep `protected-mode yes`; disable unauthenticated admin commands (FLUSHALL/FLUSHDB). |
| 15435/tcp docker->5432 | Postgres via container publish | Change compose publish to `127.0.0.1:15435:5432`; recreate container. |
| 19601/tcp docker->3000 | App via container publish | Change compose publish to `127.0.0.1:19601:3000`; recreate container. |
| 27500/tcp (unmapped) | Unknown | Identify service (`docker ps` / `ss -ltnp`), then apply intent-based firewall/authorization. |

The agent helper `SecurityAgent.ports-fix` (`spectre security --fix` path via the
`ports-fix` action) maps known ports to these hardening targets and reports anything
outside the map for manual review. It is read-only (no automatic daemon rebinds) by design;
the privileged daemon/config changes above are operator-applied.

## 4) How the audit works / reading results

- Actions: `selinux-audit`, `firewall-audit`, `ports-audit`, `secrets-scan`, `ssh-audit`, plus `ports-fix`.
- `ports-audit` reports `0.0.0.0:*` wildcard listeners and writes a `WILDCARD_PORTS` security
  incident; `ports-fix` summarizes known-bind remediations and flags unmapped ports.
- `secrets-scan` scans configured root (default repo root) for private keys / generic secrets,
  ignoring VCS, venv, cache, and installed-package trees plus `tests/` (after false-positive fix).
- `ssh-audit` reads `/etc/ssh/sshd_config` + includes and reports effective `PermitRootLogin`.
- `selinux-audit` / `firewall-audit` check enforcement/activity; `firewall-audit` fix can start firewalld.
- `--fix` applies only safe, agent-known remediations and always reports manual steps for risky ones.