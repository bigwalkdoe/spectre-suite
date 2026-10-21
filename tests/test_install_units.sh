#!/bin/bash
# Installer systemd unit expansion tests
#
# install.sh writes `User=$USER_NAME` inside quoted heredocs, so systemd units
# get the literal string `$USER_NAME` and fail with `217/USER`. These tests
# extract each service-unit template from install.sh and verify that the actual
# username is substituted when the heredoc is expanded (unquoted << EOF).
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
INSTALL="$PROJECT_ROOT/install.sh"

PASSED=0
FAILED=0
pass() { echo "✅ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "❌ $1"; FAILED=$((FAILED + 1)); }

# Extract the heredoc body for a given systemd service unit from install.sh.
extract_unit_body() {
    local unit_name="$1"
    local start_marker="cat > /etc/systemd/system/${unit_name}.service << EOF"
    local in_body=0
    local body=""
    while IFS= read -r line; do
        if [ "$in_body" -eq 0 ]; then
            if [ "$line" = "$start_marker" ]; then
                in_body=1
            fi
            continue
        fi
        if [ "$line" = "EOF" ]; then
            break
        fi
        body+="${line}"$'\n'
    done < "$INSTALL"
    printf '%s' "$body"
}

# Expand a heredoc body as bash would with unquoted << EOF, substituting
# USER_NAME with the given value. Uses a temp file to avoid shell quoting
# pitfalls with inline heredocs.
expand_body() {
    local body="$1"
    local user_name="$2"
    local tmpfile
    tmpfile=$(mktemp)
    printf '%s\n' "$body" > "$tmpfile"
    local expanded
    expanded=$(USER_NAME="$user_name" bash -c "cat <<EOF
$(cat "$tmpfile")
EOF")
    rm -f "$tmpfile"
    printf '%s' "$expanded"
}

# Each service unit referenced by install.sh.
for unit in backup maintenance performance-check network-monitor disk-space-check security-scan; do
    # The heredoc must be unquoted (<< EOF) so bash expands $USER_NAME.
    # Quoted heredocs (<< 'EOF') write the literal string $USER_NAME into the
    # unit file, and systemd then fails with 217/USER.
    if grep -qE "^cat > /etc/systemd/system/${unit}\.service << 'EOF'" "$INSTALL"; then
        fail "${unit}.service uses a quoted heredoc (<< 'EOF'); User=\$USER_NAME will not expand"
        continue
    fi
    if ! grep -qE "^cat > /etc/systemd/system/${unit}\.service << EOF" "$INSTALL"; then
        fail "${unit}.service does not use an unquoted heredoc (<< EOF)"
        continue
    fi
    pass "${unit}.service uses an unquoted heredoc so \$USER_NAME expands"

    body=$(extract_unit_body "$unit")
    if [ -z "$body" ]; then
        fail "could not extract ${unit}.service template from install.sh"
        continue
    fi

    expanded=$(expand_body "$body" "spectre-user")

    if printf '%s' "$expanded" | grep -qF 'User=$USER_NAME'; then
        fail "${unit}.service still contains literal User=\$USER_NAME after expansion"
    elif printf '%s' "$expanded" | grep -qF 'User=spectre-user'; then
        pass "${unit}.service expands User=\$USER_NAME to the actual username"
    else
        fail "${unit}.service User= line is missing or malformed after expansion"
    fi

    if printf '%s' "$expanded" | grep -qF 'Group=$USER_NAME'; then
        fail "${unit}.service still contains literal Group=\$USER_NAME after expansion"
    elif printf '%s' "$expanded" | grep -qF 'Group=spectre-user'; then
        pass "${unit}.service expands Group=\$USER_NAME to the actual group"
    else
        fail "${unit}.service Group= line is missing or malformed after expansion"
    fi
done

echo ""
echo "Installer unit expansion tests: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
