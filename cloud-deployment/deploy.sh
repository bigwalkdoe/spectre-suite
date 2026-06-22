#!/bin/bash
# Automated Cloud Deployment Script
# Combines Terraform and Ansible for complete cloud deployment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Terraform
    if ! command -v terraform >/dev/null 2>&1; then
        log_error "Terraform is not installed"
        exit 1
    fi
    
    # Check Ansible
    if ! command -v ansible >/dev/null 2>&1; then
        log_error "Ansible is not installed"
        exit 1
    fi
    
    # Check AWS CLI (if using AWS)
    if [ "$DEPLOYMENT_TARGET" = "aws" ] && ! command -v aws >/dev/null 2>&1; then
        log_warn "AWS CLI not found. Install for full AWS integration."
    fi
    
    log_info "Prerequisites check passed"
}

# Parse arguments
parse_args() {
    DEPLOYMENT_TARGET="${1:-aws}"
    ENVIRONMENT="${2:-dev}"
    INSTANCE_COUNT="${3:-2}"
    
    log_info "Deployment target: $DEPLOYMENT_TARGET"
    log_info "Environment: $ENVIRONMENT"
    log_info "Instance count: $INSTANCE_COUNT"
}

# Configure Terraform
configure_terraform() {
    log_info "Configuring Terraform..."
    
    cd "$SCRIPT_DIR/terraform"
    
    cat > terraform.tfvars << EOF
deployment_target = "$DEPLOYMENT_TARGET"
environment       = "$ENVIRONMENT"
instance_count    = $INSTANCE_COUNT
EOF
    
    case $DEPLOYMENT_TARGET in
        aws)
            echo "aws_region = \"${AWS_REGION:-us-east-1}\"" >> terraform.tfvars
            echo "aws_instance_type = \"${AWS_INSTANCE_TYPE:-t3.micro}\"" >> terraform.tfvars
            ;;
        azure)
            echo "azure_location = \"${AZURE_LOCATION:-eastus}\"" >> terraform.tfvars
            ;;
        gcp)
            echo "gcp_region = \"${GCP_REGION:-us-central1}\"" >> terraform.tfvars
            ;;
    esac
    
    log_info "Terraform configuration created"
}

# Deploy infrastructure with Terraform
deploy_infrastructure() {
    log_info "Deploying infrastructure with Terraform..."
    
    cd "$SCRIPT_DIR/terraform"
    
    # Initialize Terraform
    log_info "Initializing Terraform..."
    terraform init
    
    # Plan deployment
    log_info "Planning Terraform deployment..."
    terraform plan -out=tfplan
    
    # Confirm deployment
    read -p "Proceed with deployment? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Applying Terraform changes..."
        terraform apply tfplan
    else
        log_error "Deployment cancelled"
        exit 1
    fi
    
    # Get outputs
    log_info "Retrieving infrastructure outputs..."
    INSTANCE_IPS=$(terraform output -raw aws_instance_ips 2>/dev/null || echo "")
    
    log_info "Infrastructure deployed successfully"
    log_info "Instance IPs: $INSTANCE_IPS"
}

# Update Ansible inventory
update_inventory() {
    log_info "Updating Ansible inventory..."
    
    cd "$SCRIPT_DIR/ansible"
    
    case $ENVIRONMENT in
        dev)
            INVENTORY_FILE="inventory/dev.yml"
            ;;
        staging)
            INVENTORY_FILE="inventory/staging.yml"
            ;;
        production)
            INVENTORY_FILE="inventory/production.yml"
            ;;
        *)
            INVENTORY_FILE="inventory/${ENVIRONMENT}.yml"
            ;;
    esac
    
    # Update inventory with new instance IPs
    if [ -n "$INSTANCE_IPS" ]; then
        # Parse IPs and update inventory
        index=1
        for ip in $INSTANCE_IPS; do
            host_name="${ENVIRONMENT}-maintenance-${index}"
            
            # Create/update inventory entry
            if [ ! -f "$INVENTORY_FILE" ]; then
                cat > "$INVENTORY_FILE" << EOF
---
${ENVIRONMENT}:
  hosts:
    ${host_name}:
      ansible_host: $ip
      ansible_user: ubuntu
      cloud_deployment: true
      monitoring_enabled: true
      security_enabled: true
      environment: ${ENVIRONMENT}
      cloud_provider: ${DEPLOYMENT_TARGET}
  vars:
    project_name: system-maintenance
    installation_dir: /opt/system-maintenance
    backup_dir: /backups
EOF
            fi
            ((index++))
        done
    fi
    
    log_info "Ansible inventory updated: $INVENTORY_FILE"
}

# Wait for instances to be ready
wait_for_instances() {
    log_info "Waiting for instances to be ready..."
    
    if [ -n "$INSTANCE_IPS" ]; then
        for ip in $INSTANCE_IPS; do
            log_info "Waiting for $ip to be accessible..."
            
            max_attempts=30
            attempt=0
            
            while [ $attempt -lt $max_attempts ]; do
                if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@$ip "echo 'ready'" >/dev/null 2>&1; then
                    log_info "Instance $ip is ready"
                    break
                fi
                
                ((attempt++))
                sleep 10
            done
            
            if [ $attempt -eq $max_attempts ]; then
                log_error "Instance $ip did not become ready within timeout"
                exit 1
            fi
        done
    fi
}

# Deploy configuration with Ansible
deploy_configuration() {
    log_info "Deploying configuration with Ansible..."
    
    cd "$SCRIPT_DIR/ansible"
    
    # Run playbook
    ansible-playbook -i "$INVENTORY_FILE" playbook.yml
    
    log_info "Configuration deployed successfully"
}

# Post-deployment verification
verify_deployment() {
    log_info "Running post-deployment verification..."
    
    cd "$SCRIPT_DIR/ansible"
    
    # Check if services are running
    ansible-playbook -i "$INVENTORY_FILE" playbook.yml --tags verify
    
    # Test web dashboard
    if [ -n "$INSTANCE_IPS" ]; then
        FIRST_IP=$(echo $INSTANCE_IPS | awk '{print $1}')
        log_info "Testing web dashboard at http://$FIRST_IP:8081"
        
        if curl -s "http://$FIRST_IP:8081" >/dev/null 2>&1; then
            log_info "Web dashboard is accessible"
        else
            log_warn "Web dashboard not yet accessible (may need more time)"
        fi
    fi
    
    log_info "Deployment verification completed"
}

# Cleanup on failure
cleanup_on_failure() {
    log_warn "Cleaning up failed deployment..."
    
    cd "$SCRIPT_DIR/terraform"
    
    # Optionally destroy infrastructure on failure
    read -p "Destroy infrastructure due to deployment failure? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        terraform destroy
    fi
}

# Main deployment function
main() {
    log_info "Starting cloud deployment..."
    log_info "=========================================="
    
    # Parse arguments
    parse_args "$@"
    
    # Check prerequisites
    check_prerequisites
    
    # Configure Terraform
    configure_terraform
    
    # Deploy infrastructure
    if ! deploy_infrastructure; then
        cleanup_on_failure
        exit 1
    fi
    
    # Update inventory
    update_inventory
    
    # Wait for instances
    wait_for_instances
    
    # Deploy configuration
    if ! deploy_configuration; then
        cleanup_on_failure
        exit 1
    fi
    
    # Verify deployment
    verify_deployment
    
    log_info "=========================================="
    log_info "Cloud deployment completed successfully!"
    log_info ""
    log_info "Access Information:"
    log_info "  - Web Dashboard: http://$(echo $INSTANCE_IPS | awk '{print $1}'):8081"
    log_info "  - Grafana: http://$(echo $INSTANCE_IPS | awk '{print $1}'):3002"
    log_info "  - Prometheus: http://$(echo $INSTANCE_IPS | awk '{print $1}'):9090"
    log_info ""
    log_info "Next Steps:"
    log_info "  1. Change default Grafana password"
    log_info "  2. Configure backup destination"
    log_info "  3. Review security configurations"
    log_info "  4. Set up monitoring alerts"
}

# Handle script interruption
trap cleanup_on_failure INT TERM

# Run main function
main "$@"
