#!/bin/bash
# Backup Script Tests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Running backup script tests..."

# Test 1: Check if backup script exists
test_backup_script_exists() {
    echo "Test 1: Check if backup script exists"
    if [ -f "$PROJECT_ROOT/scripts/backups/backup-all.sh" ]; then
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
    if [ -x "$PROJECT_ROOT/scripts/backups/backup-all.sh" ]; then
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
    if bash -n "$PROJECT_ROOT/scripts/backups/backup-all.sh"; then
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
        if [ ! -f "$PROJECT_ROOT/scripts/backups/$script" ]; then
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

# Run all tests
run_all_tests() {
    local passed=0
    local failed=0
    
    test_backup_script_exists && ((passed++)) || ((failed++))
    test_backup_script_executable && ((passed++)) || ((failed++))
    test_backup_directories && ((passed++)) || ((failed++))
    test_backup_script_syntax && ((passed++)) || ((failed++))
    test_required_backup_scripts && ((passed++)) || ((failed++))
    
    echo ""
    echo "Backup Script Tests Summary:"
    echo "  Passed: $passed"
    echo "  Failed: $failed"
    echo "  Total:  $((passed + failed))"
    
    return $failed
}

# Run tests
run_all_tests
