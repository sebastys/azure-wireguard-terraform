#!/bin/bash

# Register required Azure Resource Providers for WireGuard deployment
# This script registers only the providers we actually need

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Azure CLI is available and authenticated
if ! command -v az &> /dev/null; then
    error "Azure CLI is not installed. Please install it first."
    exit 1
fi

if ! az account show &> /dev/null; then
    error "Not logged into Azure. Please run 'az login' first."
    exit 1
fi

log "Checking and registering required Azure Resource Providers..."

# Required providers for this WireGuard deployment
REQUIRED_PROVIDERS=(
    "Microsoft.Compute"      # Virtual Machines
    "Microsoft.Network"      # Networking resources
    "Microsoft.Storage"      # Storage for VM disks
)

for provider in "${REQUIRED_PROVIDERS[@]}"; do
    log "Checking provider: $provider"
    
    # Check current registration state
    state=$(az provider show --namespace "$provider" --query "registrationState" -o tsv 2>/dev/null || echo "Unknown")
    
    if [[ "$state" == "Registered" ]]; then
        log "✅ $provider is already registered"
    else
        warning "$provider is not registered (state: $state). Attempting to register..."
        
        # Register the provider
        if az provider register --namespace "$provider" --wait; then
            log "✅ Successfully registered $provider"
        else
            error "❌ Failed to register $provider"
            error "This may be due to insufficient permissions."
            error "Please contact your Azure administrator or try:"
            error "az provider register --namespace $provider"
            exit 1
        fi
    fi
done

log "🎉 All required resource providers are registered!"
echo
echo "You can now proceed with Terraform deployment:"
echo "  ./deploy.sh"
echo "  or"
echo "  terraform plan && terraform apply"