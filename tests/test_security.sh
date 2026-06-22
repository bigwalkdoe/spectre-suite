#!/bin/bash
# Security Script Tests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Running security script tests..."

# Test 1: Check if security scripts exist
test_security_scripts_exist() {
    echo "Test 1: Check if security scripts exist"
    local security_scripts=(
        "scripts/security/run-security-hardening.sh"
        "scripts/security/scan-dependencies.sh"
        "scripts/security/docker-security-hardening.sh"
        "scripts/security/install-ids-ips.sh"
        "scripts/security/advanced-threat-detection.sh"
    )
    
    local all_exist=true
    for script in "${security_scripts[@]}"; do
        if [ ! -f "$PROJECT_ROOT/$script" ]; then
            echo "❌ Missing security script: $script"
            all_exist=false
        fi
    done
    
    if $all_exist; then
        echo "✅ All security scripts exist"
        return 0
    else
        return 1
    fi
}

# Test 2: Check if security scripts are executable
test_security_scripts_executable() {
    echo "Test 2: Check if security scripts are executable"
    local security_scripts=(
        "scripts/security/run-security-hardening.sh"
        "scripts/security/scan-dependencies.sh"
        "scripts/security/docker-security-hardening.sh"
    )
    
    local all_executable=true
    for script in "${security_scripts[@]}"; do
        if [ ! -x "$PROJECT_ROOT/$script" ]; then
            echo "❌ Security script not executable: $script"
            all_executable=false
        fi
    done
    
    if $all_executable; then
        echo "✅ All security scripts are executable"
        return 0
    else
        return 1
    fi
}

# Test 3: Check if security scripts have correct syntax
test_security_scripts_syntax() {
    echo "Test 3: Check if security scripts have correct syntax"
    local syntax_errors=0
    
    for script in "$PROJECT_ROOT"/scripts/security/*.sh; do
        if [ -f "$script" ]; then
            if ! bash -n "$script"; then
                echo "❌ Syntax error in $script"
                ((syntax_errors++))
            fi
        fi
    done
    
    if [ $syntax_errors -eq 0 ]; then
        echo "✅ All security scripts have correct syntax"
        return 0
    else
        echo "❌ Found $syntax_errors scripts with syntax errors"
        return 1
    fi
}

# Test 4: Check if security configuration files exist
test_security_configurations() {
    echo "Test 4: Check if security configuration files exist"
    local config_files=(
        "prometheus/alert_rules.yml"
        "prometheus/alertmanager.yml"
    )
    
    local all_exist=true
    for config in "${config_files[@]}"; do
        if [ ! -f "$PROJECT_ROOT/$config" ]; then
            echo "❌ Missing security configuration: $config"
            all_exist=false
        fi
    done
    
    if $all_exist; then
        echo "✅ All security configuration files exist"
        return 0
    else
        return 1
    fi
}

# Test 5: Check if IDS/IPS installation script exists
test_ids_ips_script() {
    echo "Test 5: Check if IDS/IPS installation script exists"
    if [ -f "$PROJECT_ROOT/scripts/security/install-ids-ips.sh" ]; then
        echo "✅ IDS/IPS installation script exists"
        return 0
    else
        echo "❌ IDS/IPS installation script does not exist"
        return 1
    fi
}

# Run all tests
run_all_tests() {
    local passed=0
    local failed=0
    
    test_security_scripts_exist && ((passed++)) || ((failed++))
    test_security_scripts_executable && ((passed++)) || ((failed++))
    test_security_scripts_syntax && ((passed++)) || ((failed++))
    test_security_configurations && ((passed++)) || ((failed++))
    test_ids_ips_script && ((passed++)) || ((failed++))
    
    echo ""
    echo "Security Script Tests Summary:"
    echo "  Passed: $passed"
    echo "  Failed: $failed"
    echo "  Total:  $((passed + failed))"
    
    return $failed
}

# Run tests
run_all_tests
