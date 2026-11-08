#!/bin/bash
# Backup Script Tests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Running backup script tests..."

_resolve_action() { # args: relpath
    if [ -f "$PROJECT_ROOT/spectre/actions/$1" ]; then echo "$PROJECT_ROOT/spectre/actions/$1"; else return 1; fi
}

# Test 1: Check if backup script exists
test_backup_script_exists() {
    echo "Test 1: Check if backup script exists"
    if _resolve_action "backups/backup-all.sh" >/dev/null; then
        echo "✅ Backup script exists"
        return 0
    else
        echo "❌ Backup script does not exist"
        return 1
    fi
}

# Test 2: Check if backup script is executable
test_backup_script_executable() {
    echo "Test 2: Check if backup script is executable"
    local s; s=$(_resolve_action "backups/backup-all.sh" || true)
    if [ -n "$s" ] && [ -x "$s" ]; then
        echo "✅ Backup script is executable"
        return 0
    else
        echo "❌ Backup script is not executable"
        return 1
    fi
}

# Test 3: Check if backup directories can be created
test_backup_directories() {
    echo "Test 3: Check if backup directories can be created"
    local test_backup_dir="/tmp/test-backup"
    
    mkdir -p "$test_backup_dir"/{databases,docker-volumes,configurations,projects}
    
    if [ -d "$test_backup_dir/databases" ] && [ -d "$test_backup_dir/docker-volumes" ]; then
        echo "✅ Backup directories created successfully"
        rm -rf "$test_backup_dir"
        return 0
    else
        echo "❌ Failed to create backup directories"
        rm -rf "$test_backup_dir"
        return 1
    fi
}

# Test 4: Check if backup script has correct syntax
test_backup_script_syntax() {
    echo "Test 4: Check if backup script has correct syntax"
    local s; s=$(_resolve_action "backups/backup-all.sh" || true)
    if [ -n "$s" ] && bash -n "$s"; then
        echo "✅ Backup script syntax is correct"
        return 0
    else
        echo "❌ Backup script has syntax errors"
        return 1
    fi
}

# Test 5: Check if required backup scripts exist
test_required_backup_scripts() {
    echo "Test 5: Check if required backup scripts exist"
    local required_scripts=(
        "backup-databases.sh"
        "backup-docker-volumes.sh"
        "backup-configurations.sh"
        "backup-projects.sh"
    )

    local all_exist=true
    for script in "${required_scripts[@]}"; do
        if ! _resolve_action "backups/$script" >/dev/null; then
            echo "❌ Missing required script: $script"
            all_exist=false
        fi
    done

    if $all_exist; then
        echo "✅ All required backup scripts exist"
        return 0
    else
        return 1
    fi
}

# Test 6: backup-all.sh must exit non-zero when any component fails
test_backup_all_propagates_failure() {
    echo "Test 6: backup-all.sh exits non-zero when a component fails"
    local sandbox backup_all
    sandbox="$(mktemp -d "${TMPDIR:-/tmp}/backup-fail-test.XXXXXX")"
    trap 'rm -rf "$sandbox"' RETURN
    backup_all=$(_resolve_action "backups/backup-all.sh") || { echo "❌ backup-all.sh missing"; return 1; }

    mkdir -p "$sandbox/bin" "$sandbox/actions"

    # Stub docker so stubbed component scripts that call it do not fail.
    cat > "$sandbox/bin/docker" <<'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$sandbox/bin/docker"

    # One component fails; the others succeed. Canonical backup-all.sh runs
    # siblings from its own SCRIPT_DIR.
    cat > "$sandbox/actions/backup-databases.sh" <<'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "$sandbox/actions/backup-databases.sh"

    cat > "$sandbox/actions/backup-docker-volumes.sh" <<'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$sandbox/actions/backup-docker-volumes.sh"

    cat > "$sandbox/actions/backup-configurations.sh" <<'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$sandbox/actions/backup-configurations.sh"

    cp "$backup_all" "$sandbox/actions/backup-all.sh"
    chmod +x "$sandbox/actions/backup-all.sh"

    BACKUP_DIR="$sandbox/backups" \
    BACKUP_STATE_DIR="$sandbox/state" \
    PATH="$sandbox/bin:$PATH" \
        "$sandbox/actions/backup-all.sh" >"$sandbox/out.log" 2>&1
    local status=$?

    if [ "$status" -ne 0 ]; then
        echo "✅ backup-all.sh exited $status on component failure"
        return 0
    else
        echo "❌ backup-all.sh exited $status despite a component failure (see $sandbox/out.log)"
        cat "$sandbox/out.log" >&2 || true
        return 1
    fi
}

# Run all tests
run_all_tests() {
    local passed=0
    local failed=0
    
    if test_backup_script_exists; then
        ((passed+=1))
    else
        ((failed+=1))
    fi
    if test_backup_script_executable; then
        ((passed+=1))
    else
        ((failed+=1))
    fi
    if test_backup_directories; then
        ((passed+=1))
    else
        ((failed+=1))
    fi
    if test_backup_script_syntax; then
        ((passed+=1))
    else
        ((failed+=1))
    fi
    if test_required_backup_scripts; then
        ((passed+=1))
    else
        ((failed+=1))
    fi
    if test_backup_all_propagates_failure; then
        ((passed+=1))
    else
        ((failed+=1))
    fi
    
    echo ""
    echo "Backup Script Tests Summary:"
    echo "  Passed: $passed"
    echo "  Failed: $failed"
    echo "  Total:  $((passed + failed))"
    
    return $failed
}

# Run tests
run_all_tests
