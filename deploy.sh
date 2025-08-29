#!/bin/bash

# Azure WireGuard VPN Deployment Script
# This script helps deploy the WireGuard VPN server using Terraform

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Terraform is installed
    if ! command -v terraform &> /dev/null; then
        error "Terraform is not installed. Please install Terraform first."
        error "Visit: https://learn.hashicorp.com/tutorials/terraform/install-cli"
        exit 1
    fi
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install Azure CLI first."
        error "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if logged into Azure
    if ! az account show &> /dev/null; then
        error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    log "Prerequisites check passed!"
}

# Generate SSH key if it doesn't exist
setup_ssh_key() {
    local ssh_key_path="$HOME/.ssh/id_rsa"
    
    if [[ ! -f "$ssh_key_path" ]]; then
        warning "SSH key not found at $ssh_key_path"
        read -p "Do you want to generate a new SSH key? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log "Generating SSH key..."
            ssh-keygen -t rsa -b 4096 -f "$ssh_key_path" -N ""
            log "SSH key generated at $ssh_key_path"
        else
            error "SSH key is required for VM access. Exiting."
            exit 1
        fi
    fi
    
    # Export the public key for use in terraform.tfvars
    export SSH_PUBLIC_KEY=$(cat "$ssh_key_path.pub")
    log "SSH public key loaded"
}

# Create terraform.tfvars if it doesn't exist
create_tfvars() {
    if [[ ! -f "terraform.tfvars" ]]; then
        log "Creating terraform.tfvars file..."
        
        # Get user input
        read -p "Enter Azure region (default: East US): " location
        location=${location:-"East US"}
        
        read -p "Enter admin username (default: azureuser): " admin_username
        admin_username=${admin_username:-"azureuser"}
        
        read -p "Enter number of client configs to generate (default: 10): " client_count
        client_count=${client_count:-10}
        
        # Create terraform.tfvars
        cat > terraform.tfvars << EOF
# Azure WireGuard VPN Configuration
location = "$location"
admin_username = "$admin_username"
ssh_public_key = "$SSH_PUBLIC_KEY"
client_count = $client_count

# Resource tags
tags = {
  Environment   = "Production"
  Project       = "WireGuard-VPN"
  ManagedBy     = "Terraform"
  DeployedDate  = "$(date +%Y-%m-%d)"
}
EOF
        
        log "terraform.tfvars created successfully"
    else
        info "terraform.tfvars already exists, using existing configuration"
    fi
}

# Deploy infrastructure
deploy() {
    log "Initializing Terraform..."
    terraform init
    
    log "Validating Terraform configuration..."
    terraform validate
    
    log "Planning Terraform deployment..."
    terraform plan
    
    echo
    read -p "Do you want to proceed with the deployment? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Deploying WireGuard VPN server..."
        terraform apply -auto-approve
        
        log "Deployment completed successfully!"
        show_connection_info
    else
        info "Deployment cancelled by user"
        exit 0
    fi
}

# Show connection information
show_connection_info() {
    echo
    echo "========================================"
    echo "🎉 WireGuard VPN Server Deployed!"
    echo "========================================"
    
    # Get outputs from Terraform
    public_ip=$(terraform output -raw public_ip_address)
    ssh_command=$(terraform output -raw ssh_connection_command)
    download_command=$(terraform output -raw download_configs_command)
    
    echo "📍 Server IP: $public_ip"
    echo "🔐 SSH Access: $ssh_command"
    echo
    echo "⏱️  Please wait 3-5 minutes for the server setup to complete."
    echo
    echo "📥 To download client configurations:"
    echo "   $download_command"
    echo
    echo "📋 To view the server summary:"
    echo "   ssh $(terraform output -raw admin_username)@$public_ip 'cat /home/$(terraform output -raw admin_username)/wireguard-summary.txt'"
    echo
    echo "🔒 Security Note:"
    echo "   Consider disabling SSH port 22 after downloading configs:"
    echo "   Go to Azure Portal > Network Security Group > Remove SSH rule"
    echo
    echo "========================================"
}

# Cleanup function
cleanup() {
    read -p "Are you sure you want to destroy all resources? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        warning "Destroying all resources..."
        terraform destroy -auto-approve
        log "All resources have been destroyed"
    else
        info "Cleanup cancelled"
    fi
}

# Show help
show_help() {
    echo "Azure WireGuard VPN Deployment Script"
    echo
    echo "Usage: $0 [COMMAND]"
    echo
    echo "Commands:"
    echo "  deploy     Deploy the WireGuard VPN server (default)"
    echo "  cleanup    Destroy all deployed resources"
    echo "  plan       Show deployment plan without applying"
    echo "  output     Show deployment outputs"
    echo "  help       Show this help message"
    echo
}

# Main execution
case "${1:-deploy}" in
    deploy)
        check_prerequisites
        setup_ssh_key
        create_tfvars
        deploy
        ;;
    cleanup)
        check_prerequisites
        cleanup
        ;;
    plan)
        check_prerequisites
        terraform plan
        ;;
    output)
        terraform output
        ;;
    help)
        show_help
        ;;
    *)
        error "Unknown command: $1"
        show_help
        exit 1
        ;;
esac