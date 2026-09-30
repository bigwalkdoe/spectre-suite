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
