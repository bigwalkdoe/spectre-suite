#!/usr/bin/env bash
# Installs the user systemd path/service units that process dashboard action triggers.
# Adjust REPO_DIR if this repo lives elsewhere.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UNIT_SRC="$REPO_DIR/systemd/dashboard-actions"
UNIT_DST="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

mkdir -p "$UNIT_DST"
install -m 0644 "$UNIT_SRC/spectre-dashboard-actions.path" "$UNIT_DST/"
install -m 0644 "$UNIT_SRC/spectre-dashboard-actions.service" "$UNIT_DST/"

# Rewrite %h/dev/github/spectre-suite to the actual repo path in installed units
# so the handler works regardless of checkout location.
escaped_repo=$(printf '%s' "$REPO_DIR" | sed 's/[\/&]/\\&/g')
sed -i "s|%h/dev/github/spectre-suite|$escaped_repo|g" "$UNIT_DST/spectre-dashboard-actions.path" "$UNIT_DST/spectre-dashboard-actions.service"

systemctl --user daemon-reload
systemctl --user enable --now spectre-dashboard-actions.path

echo "Installed dashboard-actions handler units to $UNIT_DST"
echo "Repo: $REPO_DIR"
systemctl --user status --no-pager spectre-dashboard-actions.path || true
