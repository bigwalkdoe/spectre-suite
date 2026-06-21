#!/bin/bash
# Application Dependency Vulnerability Scanner

echo "Scanning application dependencies for vulnerabilities..."

# Function to scan a project directory
scan_project() {
    local project_dir=$1
    local project_name=$(basename "$project_dir")
    
    if [ ! -d "$project_dir" ]; then
        echo "Project directory not found: $project_dir"
        return 1
    fi
    
    echo "Scanning $project_name..."
    
    # Check for package.json and run npm audit if available
    if [ -f "$project_dir/package.json" ]; then
        echo "Found Node.js project, running npm audit..."
        cd "$project_dir"
        npm audit --json 2>/dev/null || echo "npm audit not available or failed"
        cd - >/dev/null
    fi
    
    # Check for requirements.txt and run safety if available
    if [ -f "$project_dir/requirements.txt" ]; then
        echo "Found Python project, checking dependencies..."
        if command -v safety >/dev/null 2>&1; then
            safety check -r "$project_dir/requirements.txt" 2>/dev/null || echo "safety check failed"
        else
            echo "safety not installed, skipping Python dependency check"
        fi
    fi
    
    # Check for go.mod and run go vuln if available
    if [ -f "$project_dir/go.mod" ]; then
        echo "Found Go project, checking dependencies..."
        if command -v govulncheck >/dev/null 2>&1; then
            cd "$project_dir"
            govulncheck ./... 2>/dev/null || echo "go vuln check failed"
            cd - >/dev/null
        else
            echo "govulncheck not installed, skipping Go dependency check"
        fi
    fi
}

# Scan Guardrail-AI project
scan_project "/home/deon/projects/Guardrail-AI"

# Scan Modelink project
scan_project "/home/deon/projects/Modelink"

# Scan PharmiQ project
scan_project "/home/deon/projects/PharmiQ"

echo "Dependency scanning completed!"
