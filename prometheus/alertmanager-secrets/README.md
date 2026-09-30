# Alertmanager secrets

One-value files read by `alertmanager.yml` via the `*_file` options. Alertmanager
does **not** expand `${VAR}` in its config file, so credentials cannot be
interpolated there.

Slack is the only notification channel. Populate it with
`scripts/setup-notification-channels.sh`, which writes the value from the
environment and chmods it 0600. Contents are gitignored.

| File | Environment variable |
|------|----------------------|
| `slack_webhook_url` | `SLACK_WEBHOOK_URL` |

Re-running the script is incremental: an unset variable keeps any existing file,
so a working webhook survives a re-run.

## Choosing the channel

The channel is whatever channel the webhook was created in. Alertmanager sends
`channel`, `username` and `icon_emoji` in the payload, but Slack ignores them for
incoming webhooks, so those fields are deliberately absent from
`alertmanager.yml` rather than being misleading. Severity is carried by the
attachment `color` (`danger` / `warning` / `good`) and the title prefix instead.

## Verifying delivery

```sh
./scripts/setup-notification-channels.sh --test
```

`amtool check-config` is not a delivery test: `*_file` options are not
existence-checked, so it reports success with the webhook missing. Only `--test`,
which posts a self-resolving critical alert and watches the dispatcher log,
distinguishes "accepted" from "delivered". It also prints the renderer error when
delivery fails, which is usually the fastest way to see a wrong path or a
revoked webhook.

The script exits non-zero while no webhook is configured, so it is safe to use in
CI or a bootstrap check.

## Why `user: root` on the alertmanager service

This directory is mode 0700 owned by the host user, and the image defaults to
uid 65534 (`nobody`), which cannot traverse it. Every notification then failed
with:

```
could not read /etc/alertmanager/secrets/slack_webhook_url: permission denied
```

This surfaces only at notification time. Config loading succeeds, `/-/ready`
returns 200, and Prometheus reports Alertmanager as healthy, so the failure is
invisible until an alert actually needs to be delivered. The setup script now
reads the secret back from inside the container and fails loudly, rather than
trusting the host-side permissions.

## Why the Compose bind mounts use `:z`

Every config bind mount in `docker-compose.monitoring.yml` carries a shared
SELinux label (`:z`). Without it, the host file keeps whatever MCS category it
was created with while each container is assigned its own, so the mount is
unreadable *even by root* and Alertmanager crash-loops on its own config with
`permission denied`. Because the label lives on the inode, any rewrite of the
file — `git checkout`, `git pull`, `sed -i` — resets it, so the failure appears
on an ordinary pull rather than at deploy time. `scripts/check-config-consistency.sh`
fails if any bind mount loses the label.
