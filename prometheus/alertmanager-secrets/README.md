# Alertmanager secrets

One-value files read by `alertmanager.yml` via the `*_file` options. Alertmanager
does **not** expand `${VAR}` in its config file, so credentials cannot be
interpolated there.

Populate them with `scripts/setup-notification-channels.sh`, which writes each
value from the environment and chmods it 0600. Contents are gitignored.

| File | Environment variable |
|------|----------------------|
| `smtp_username` | `SMTP_USERNAME` |
| `smtp_password` | `SMTP_PASSWORD` |
| `slack_webhook_url` | `SLACK_WEBHOOK_URL` |
| `pagerduty_routing_key` | `PAGERDUTY_ROUTING_KEY` |

`smtp_username` has no `*_file` equivalent in the receiver config, so it is set
inline as `auth_username` in `alertmanager.yml`; adjust that value to match.

Re-running the script is incremental: an unset variable keeps any existing file,
so channels can be added one at a time.

## Two things the script cannot configure for you

1. **The recipient address.** `smtp_from` and each receiver's `to:` are
   hardcoded to `alertmanager@example.com` in `alertmanager.yml` and nothing
   interpolates them. Change them to a real address or mail goes nowhere. The
   script warns while this placeholder is still present.

2. **SMTP host.** `smtp_smarthost` is `smtp.gmail.com:587`. Use your own relay,
   or a local sink for testing.

## Verifying delivery

```sh
./scripts/setup-notification-channels.sh --test
```

`amtool check-config` is not a delivery test: `*_file` options are not
existence-checked, so it reports success with every secret missing. Only
`--test`, which posts a self-resolving critical alert and watches the
dispatcher log, distinguishes "accepted" from "delivered".

The script exits non-zero while any channel is unconfigured, so it is safe to
use in CI or a bootstrap check.

## Why `user: root` on the alertmanager service

This directory is mode 0700 owned by the host user, and the image defaults to
uid 65534 (`nobody`), which cannot traverse it. Every notification then failed
with:

```
could not read /etc/alertmanager/secrets/smtp_password: permission denied
```

This surfaces only at notification time. Config loading succeeds, `/-/ready`
returns 200, and Prometheus reports Alertmanager as healthy, so the failure is
invisible until an alert actually needs to be delivered. The setup script now
reads each secret back from inside the container and fails loudly, rather than
trusting the host-side permissions.
