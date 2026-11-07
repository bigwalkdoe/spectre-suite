#!/bin/bash
# Spectre Security Baseline Alerting (suite-canonical, additive)
# Sends notifications via webhook/email/Slack. Compatible with spectre-security
# interface: alerting.sh <level> <message> <details>
set -euo pipefail

: "${HOME:=$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6 2>/dev/null || true)}"
export HOME="${HOME:-/root}"

WEBHOOK_URL="${SECURITY_WEBHOOK_URL:-}"
SLACK_WEBHOOK="${SECURITY_SLACK_WEBHOOK:-}"
EMAIL_TO="${SECURITY_EMAIL_TO:-}"
EMAIL_FROM="${SECURITY_EMAIL_FROM:-security@localhost}"
SMTP_SERVER="${SECURITY_SMTP_SERVER:-localhost}"
SMTP_PORT="${SECURITY_SMTP_PORT:-25}"

ALERT_LEVEL="${1:-warning}"
MESSAGE="${2:-Security alert}"
DETAILS="${3:-}"
TIMESTAMP=$(date -Iseconds 2>/dev/null || date -u '+%Y-%m-%dT%H:%M:%SZ')
HOSTNAME=$(hostname 2>/dev/null || echo unknown)

send_webhook() {
    local url="$1" payload="$2"
    [ -n "$url" ] || return 1
    curl -s -X POST "$url" -H "Content-Type: application/json" -d "$payload" --max-time 10 >/dev/null 2>&1
}

send_slack() {
    local webhook="$1" text="$2" color="$3"
    [ -n "$webhook" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1
    local payload
    payload=$(jq -n --arg text "$text" --arg color "$color" --arg timestamp "$TIMESTAMP" --arg hostname "$HOSTNAME" \
      '{attachments:[{color:$color,title:("Security Alert: "+$hostname),text:$text,footer:"Spectre Security Baseline",ts:(($timestamp|fromdateiso8601?)//now)}]}')
    send_webhook "$webhook" "$payload"
}

send_email() {
    local to="$1" subject="$2" body="$3"
    [ -n "$to" ] && command -v sendmail >/dev/null 2>&1 || return 1
    { echo "To: $to"; echo "From: $EMAIL_FROM"; echo "Subject: $subject"; echo "Content-Type: text/plain"; echo; echo "$body"; } | sendmail -t 2>/dev/null
}

alert() {
    local level="$1" message="$2" details="$3" color="warning" sent=false
    case "$level" in critical) color="danger";; warning) color="warning";; info) color="good";; esac
    local full_message="*Level:* $level
*Message:* $message
*Host:* $HOSTNAME
*Time:* $TIMESTAMP"
    [ -n "$details" ] && full_message="$full_message
*Details:*
\`\`\`
$details
\`\`\`"
    send_slack "$SLACK_WEBHOOK" "$full_message" "$color" && { echo "Slack notification sent"; sent=true; } || true
    if [ -n "$WEBHOOK_URL" ] && command -v jq >/dev/null 2>&1; then
        local payload
        payload=$(jq -n --arg level "$level" --arg message "$message" --arg details "$details" --arg timestamp "$TIMESTAMP" --arg hostname "$HOSTNAME" \
          '{level:$level,message:$message,details:$details,timestamp:$timestamp,hostname:$hostname,source:"spectre-suite-baseline"}')
        send_webhook "$WEBHOOK_URL" "$payload" && { echo "Webhook notification sent"; sent=true; } || true
    fi
    send_email "$EMAIL_TO" "[SECURITY $level] $message" "$full_message" && { echo "Email notification sent"; sent=true; } || true
    if [ "$sent" = false ]; then
        echo "No notification channels configured/sent (set SECURITY_WEBHOOK_URL, SECURITY_SLACK_WEBHOOK, SECURITY_EMAIL_TO)"
        return 1
    fi
    return 0
}

if [ "${BASH_SOURCE[0]-$0}" = "${0}" ]; then
    alert "$ALERT_LEVEL" "$MESSAGE" "$DETAILS"
fi
