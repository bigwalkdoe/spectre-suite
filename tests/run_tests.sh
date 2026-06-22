#!/bin/bash
# Main Test Runner for System Maintenance Suite

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=========================================="
echo "System Maintenance Suite Test Suite"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Function to run a test suite
run_test_suite() {
    local test_script=$1
    local test_name=$2
    
    echo "Running $test_name..."
    echo "------------------------------------------"
    
    if [ -x "$test_script" ]; then
        if "$test_script"; then
            echo -e "${GREEN}✅ $test_name: PASSED${NC}"
            ((PASSED_TESTS++))
        else
            echo -e "${RED}❌ $test_name: FAILED${NC}"
            ((FAILED_TESTS++))
        fi
    else
        echo -e "${YELLOW}⚠️  $test_name: SKIPPED (not executable)${NC}"
    fi
    
    ((TOTAL_TESTS++))
    echo ""
}

# Function to check script syntax
check_script_syntax() {
    echo "Checking script syntax..."
    echo "------------------------------------------"
    
    local syntax_errors=0
    local script_count=0
    
    for script in "$PROJECT_ROOT"/scripts/**/*.sh "$PROJECT_ROOT"/scripts/*/*.sh; do
        if [ -f "$script" ]; then
            ((script_count++))
            if ! bash -n "$script"; then
                echo -e "${RED}❌ Syntax error in $script${NC}"
                ((syntax_errors++))
            fi
        fi
    done
    
    if [ $syntax_errors -eq 0 ]; then
        echo -e "${GREEN}✅ All $script_count scripts have correct syntax${NC}"
        ((PASSED_TESTS++))
    else
        echo -e "${RED}❌ Found syntax errors in $syntax_errors scripts${NC}"
        ((FAILED_TESTS++))
    fi
    
    ((TOTAL_TESTS++))
    echo ""
}

# Function to check required files
check_required_files() {
    echo "Checking required files..."
    echo "------------------------------------------"
    
    local required_files=(
        "README.md"
        "install.sh"
        "scripts/detect-distribution.sh"
        "scripts/deploy-monitoring.sh"
    )
    
    local missing_files=0
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$PROJECT_ROOT/$file" ]; then
            echo -e "${RED}❌ Missing required file: $file${NC}"
            ((missing_files++))
        fi
    done
    
    if [ $missing_files -eq 0 ]; then
        echo -e "${GREEN}✅ All required files present${NC}"
        ((PASSED_TESTS++))
    else
        echo -e "${RED}❌ Missing $missing_files required files${NC}"
        ((FAILED_TESTS++))
    fi
    
    ((TOTAL_TESTS++))
    echo ""
}

# Function to check directory structure
check_directory_structure() {
    echo "Checking directory structure..."
    echo "------------------------------------------"
    
    local required_dirs=(
        "scripts"
        "scripts/backups"
        "scripts/security"
        "scripts/maintenance"
        "scripts/network"
        "scripts/performance"
        "scripts/ml-anomaly"
        "prometheus"
        "grafana-dashboards"
        "grafana-provisioning"
        "systemd"
        "cloud-deployment"
        "docs"
        "examples"
        "tests"
        "web-dashboard"
    )
    
    local missing_dirs=0
    
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$PROJECT_ROOT/$dir" ]; then
            echo -e "${RED}❌ Missing required directory: $dir${NC}"
            ((missing_dirs++))
        fi
    done
    
    if [ $missing_dirs -eq 0 ]; then
        echo -e "${GREEN}✅ All required directories present${NC}"
        ((PASSED_TESTS++))
    else
        echo -e "${RED}❌ Missing $missing_dirs required directories${NC}"
        ((FAILED_TESTS++))
    fi
    
    ((TOTAL_TESTS++))
    echo ""
}

# Function to check executable permissions
check_executable_permissions() {
    echo "Checking executable permissions..."
    echo "------------------------------------------"
    
    local permission_errors=0
    
    for script in "$PROJECT_ROOT"/scripts/**/*.sh "$PROJECT_ROOT"/scripts/*/*.sh; do
        if [ -f "$script" ]; then
            if [ ! -x "$script" ]; then
                echo -e "${YELLOW}⚠️  Script not executable: $script${NC}"
                ((permission_errors++))
            fi
        fi
    done
    
    if [ $permission_errors -eq 0 ]; then
        echo -e "${GREEN}✅ All scripts have executable permissions${NC}"
        ((PASSED_TESTS++))
    else
        echo -e "${YELLOW}⚠️  $permission_errors scripts lack executable permissions${NC}"
        ((FAILED_TESTS++))
    fi
    
    ((TOTAL_TESTS++))
    echo ""
}

# Function to check configuration files
check_configuration_files() {
    echo "Checking configuration files..."
    echo "------------------------------------------"
    
    local config_files=(
        "prometheus/prometheus.yml"
        "prometheus/alert_rules.yml"
        "prometheus/alertmanager.yml"
        "docker-compose.monitoring.yml"
    )
    
    local missing_configs=0
    
    for config in "${config_files[@]}"; do
        if [ ! -f "$PROJECT_ROOT/$config" ]; then
            echo -e "${RED}❌ Missing configuration file: $config${NC}"
            ((missing_configs++))
        fi
    done
    
    if [ $missing_configs -eq 0 ]; then
        echo -e "${GREEN}✅ All configuration files present${NC}"
        ((PASSED_TESTS++))
    else
        echo -e "${RED}❌ Missing $missing_configs configuration files${NC}"
        ((FAILED_TESTS++))
    fi
    
    ((TOTAL_TESTS++))
    echo ""
}

# Main test execution
main() {
    cd "$PROJECT_ROOT"
    
    # Run structural checks
    check_required_files
    check_directory_structure
    check_executable_permissions
    check_configuration_files
    check_script_syntax
    
    # Run component tests
    run_test_suite "$SCRIPT_DIR/test_backup.sh" "Backup Script Tests"
    run_test_suite "$SCRIPT_DIR/test_security.sh" "Security Script Tests"
    
    # Print summary
    echo "=========================================="
    echo "Test Summary"
    echo "=========================================="
    echo "Total Tests:  $TOTAL_TESTS"
    echo -e "Passed:       ${GREEN}$PASSED_TESTS${NC}"
    echo -e "Failed:       ${RED}$FAILED_TESTS${NC}"
    echo ""
    
    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "${GREEN}✅ All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}❌ Some tests failed${NC}"
        exit 1
    fi
}

# Run main function
main
