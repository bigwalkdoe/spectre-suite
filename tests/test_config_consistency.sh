#!/bin/bash
# Config Consistency Gate Tests
#
# These are negative controls. The gate's whole purpose is to catch
# configuration that looks plausible but cannot work, and a check that only ever
# sees good input proves nothing: an earlier version of the alertmanager
# cross-check used a regex with a required literal bracket, matched nothing at
# all, and reported success on every run.
#
# Each case copies the real configuration into a temporary tree and injects one
# fault, so the repository is never modified.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Running config consistency gate tests..."

PASSED=0
FAILED=0

pass() { echo "✅ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "❌ $1"; FAILED=$((FAILED + 1)); }

# Build a throwaway tree with the layout the gate expects. It derives the project
# root from its own location, so copying the script into $TMP/scripts/ is enough
# to redirect every path it reads.
stage() {
    local dest
    dest="$(mktemp -d)"
    mkdir -p "$dest/scripts" "$dest/prometheus" "$dest/web-dashboard"
    cp "$PROJECT_ROOT/scripts/check-config-consistency.sh" "$dest/scripts/"
    cp "$PROJECT_ROOT/prometheus/prometheus.yml" "$dest/prometheus/"
    cp "$PROJECT_ROOT/prometheus/alert_rules.yml" "$dest/prometheus/"
    cp "$PROJECT_ROOT/prometheus/alertmanager.yml" "$dest/prometheus/"
    cp "$PROJECT_ROOT/docker-compose.monitoring.yml" "$dest/"
    cp "$PROJECT_ROOT/web-dashboard/nginx.conf" "$dest/web-dashboard/"
    echo "$dest"
}

# Run the gate in a staged tree. Echoes combined output; returns its exit status.
gate() {
    "$1/scripts/check-config-consistency.sh" 2>&1
}

# expect_pass <label> <tree>
expect_pass() {
    local label="$1" tree="$2" out
    if out="$(gate "$tree")"; then
        pass "$label (gate accepted valid configuration)"
    else
        fail "$label (gate rejected valid configuration)"
        printf '%s\n' "$out" | sed 's/^/     /'
    fi
}

# expect_fail <label> <tree> <expected substring>
expect_fail() {
    local label="$1" tree="$2" needle="$3" out
    if out="$(gate "$tree")"; then
        fail "$label (gate passed a broken configuration)"
    elif printf '%s' "$out" | grep -qF "$needle"; then
        pass "$label"
    else
        fail "$label (gate failed, but not for the expected reason)"
        printf '%s\n' "$out" | sed 's/^/     /'
    fi
}

# ---------------------------------------------------------------------------
# 1. The real configuration must pass.
# ---------------------------------------------------------------------------
TREE="$(stage)"
expect_pass "unmodified configuration is accepted" "$TREE"
rm -rf "$TREE"

# ---------------------------------------------------------------------------
# 2. A route on an alertname that no rule defines can never match. This is the
#    Watchdog case: alertmanager.yml had a watchdog-receiver route and no
#    Watchdog alert behind it.
# ---------------------------------------------------------------------------
TREE="$(stage)"
sed -i "s/alertname: 'Watchdog'/alertname: 'NoSuchAlert'/" "$TREE/prometheus/alertmanager.yml"
expect_fail "route on an undefined alertname is rejected" "$TREE" "NoSuchAlert"
rm -rf "$TREE"

# ---------------------------------------------------------------------------
# 3. Inhibition rules naming alertnames that do not exist. The shipped config had
#    two, referring to InstanceDown and InstanceHealthcheck.
# ---------------------------------------------------------------------------
TREE="$(stage)"
sed -i "s/alertname: 'UptimeCheckFailed'/alertname: 'InstanceDown'/; \
        s/alertname: 'HighEndpointLatency'/alertname: 'InstanceHealthcheck'/" \
    "$TREE/prometheus/alertmanager.yml"
expect_fail "inhibition naming an undefined alertname is rejected" "$TREE" "InstanceDown"
rm -rf "$TREE"

# ---------------------------------------------------------------------------
# 4. A route pointing at a receiver that is not defined drops alerts silently.
# ---------------------------------------------------------------------------
TREE="$(stage)"
sed -i "s/receiver: 'watchdog-receiver'/receiver: 'ghost-receiver'/" \
    "$TREE/prometheus/alertmanager.yml"
expect_fail "route to an undefined receiver is rejected" "$TREE" "ghost-receiver"
rm -rf "$TREE"

# ---------------------------------------------------------------------------
# 5. Alertmanager bind-mounts a 0700 secrets directory. Without an explicit
#    user: it runs as uid 65534, cannot read the secrets, and every
#    notification fails at send time while /-/ready still returns 200.
# ---------------------------------------------------------------------------
TREE="$(stage)"
python3 - "$TREE/docker-compose.monitoring.yml" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
before = text
text = text.replace(
    "    user: root\n    ports:\n      - \"127.0.0.1:9093:9093\"",
    "    ports:\n      - \"127.0.0.1:9093:9093\"",
)
assert text != before, "fixture did not match: alertmanager user: line not found"
open(path, "w").write(text)
PY
expect_fail "alertmanager without user: is rejected" "$TREE" "nobody"
rm -rf "$TREE"

# ---------------------------------------------------------------------------
# 6. The gate must not pass vacuously. An empty rule file leaves every
#    alertname reference dangling, which is the same class of fault as case 2
#    and confirms the extraction did not simply return nothing.
# ---------------------------------------------------------------------------
TREE="$(stage)"
printf 'groups: []\n' > "$TREE/prometheus/alert_rules.yml"
expect_fail "empty alert_rules.yml is rejected" "$TREE" "Watchdog"
rm -rf "$TREE"

# ---------------------------------------------------------------------------
# 7. A scrape target naming a service that does not exist resolves to a
#    permanently-down target. This is the check the gate originally existed for.
# ---------------------------------------------------------------------------
TREE="$(stage)"
# Targets are quoted in prometheus.yml, so match the bare host:port rather than
# a delimiter-sensitive pattern.
sed -i 's/alertmanager:9093/alertmanger:9093/g' "$TREE/prometheus/prometheus.yml"
expect_fail "misspelled scrape target is rejected" "$TREE" "alertmanger"
rm -rf "$TREE"

# ---------------------------------------------------------------------------
# 8. A memory limit attached to a network instead of a service applies to
#    nothing, silently.
# ---------------------------------------------------------------------------
TREE="$(stage)"
python3 - "$TREE/docker-compose.monitoring.yml" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
before = text
text = text.replace(
    "  monitoring:\n    driver: bridge",
    "  monitoring:\n    driver: bridge\n    mem_limit: 999g",
)
assert text != before, "fixture did not match: monitoring network block not found"
open(path, "w").write(text)
PY
expect_fail "memory limit on a network is rejected" "$TREE" "network or volume"
rm -rf "$TREE"

echo ""
echo "Config consistency tests: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
