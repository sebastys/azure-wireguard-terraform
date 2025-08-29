# Azure WireGuard VPN Server - Terraform Deployment

This Terraform project deploys a WireGuard VPN server on Azure with automatic client configuration generation, based on the [AzureWireGuard](https://github.com/vijayshinva/AzureWireGuard) Bicep template but converted to Terraform.

## 🚀 Features

- **Automated WireGuard Installation**: Complete server setup with one Terraform apply
- **Multiple Client Configs**: Generates configurable number of client configurations (default: 10)
- **QR Codes**: Generates QR codes for easy mobile client setup
- **Security Hardened**: UFW firewall, iptables NAT rules, and proper key management
- **Azure Integration**: Uses Azure Network Security Groups and Public IP with FQDN
- **Scalable VM Sizes**: Supports multiple VM sizes with accelerated networking
- **Comprehensive Outputs**: Provides all necessary connection information

## 📋 Prerequisites

1. **Azure CLI** installed and authenticated (`az login`)
2. **Terraform** >= 1.0 installed
3. **SSH Key Pair** for VM access (auto-generated if needed)
4. **Azure Subscription** with sufficient permissions

## 🛠️ Quick Start

### Option 1: Using the Deploy Script (Recommended)

```bash
# Make the script executable
chmod +x deploy.sh

# Deploy everything with interactive setup
./deploy.sh

# Or use specific commands
./deploy.sh deploy   # Deploy infrastructure
./deploy.sh plan     # Show plan only
./deploy.sh cleanup  # Destroy resources
./deploy.sh help     # Show help
```

### Option 2: Manual Deployment

#### 1. Setup SSH Keys

```bash
# Generate SSH key if you don't have one
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
```

#### 2. Configure Variables

```bash
# Copy example file and edit
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
nano terraform.tfvars
```

#### 3. Deploy

```bash
# Initialize Terraform
terraform init

# Plan deployment
terraform plan

# Apply deployment
terraform apply
```

## 📁 File Structure

```
azure-wireguard-terraform/
├── main.tf                      # Main Terraform configuration
├── variables.tf                 # Variable definitions
├── outputs.tf                   # Output definitions
├── terraform.tfvars.example     # Example variables file
├── deploy.sh                    # Automated deployment script
├── README.md                    # This file
└── scripts/
    └── install_wireguard.sh     # WireGuard installation script
```

## ⚙️ Configuration Options

### Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `location` | Azure region | `"East US"` | No |
| `admin_username` | VM admin username | `"azureuser"` | No |
| `ssh_public_key` | SSH public key for VM access | - | **Yes** |
| `vm_size` | Azure VM size | `"Standard_B2s"` | No |
| `wireguard_port` | WireGuard listening port | `51820` | No |
| `wireguard_subnet` | VPN subnet for clients | `"10.13.13.0/24"` | No |
| `client_count` | Number of client configs | `10` | No |
| `client_dns` | DNS server for clients | `"1.1.1.1"` | No |
| `tags` | Resource tags | See example | No |

### Supported VM Sizes

- `Standard_B1s` (1 vCPU, 1 GB RAM) - Basic
- `Standard_B2s` (2 vCPU, 4 GB RAM) - **Recommended**
- `Standard_B1ms` (1 vCPU, 2 GB RAM)
- `Standard_B2ms` (2 vCPU, 8 GB RAM)
- `Standard_DS1_v2` (1 vCPU, 3.5 GB RAM)
- `Standard_DS2_v2` (2 vCPU, 7 GB RAM)
- `Standard_D2s_v3` (2 vCPU, 8 GB RAM)

## 📥 After Deployment

### 1. Wait for Setup (3-5 minutes)

The VM extension will automatically:
- Install WireGuard and dependencies
- Generate server and client keys
- Create client configuration files
- Configure firewall and NAT rules
- Start WireGuard service

### 2. Download Client Configurations

```bash
# Get the SSH command from Terraform output
terraform output ssh_connection_command

# Download all client configs
scp azureuser@YOUR_SERVER_IP:/home/azureuser/wg0-client-*.conf ./

# Or download specific client
scp azureuser@YOUR_SERVER_IP:/home/azureuser/wg0-client-1.conf ./
```

### 3. View Server Information

```bash
# SSH to server
ssh azureuser@YOUR_SERVER_IP

# View summary
cat wireguard-summary.txt

# View QR code for mobile (client 1)
cat wg0-client-1.qr

# Check WireGuard status
sudo wg show
```

## 📱 Client Setup

### Desktop Clients (Windows/macOS/Linux)

1. Install WireGuard client from [wireguard.com](https://www.wireguard.com/install/)
2. Import the downloaded `.conf` file
3. Connect to the VPN

### Mobile Clients (iOS/Android)

1. Install WireGuard app from App Store/Play Store
2. Scan the QR code displayed with `cat wg0-client-X.qr`
3. Connect to the VPN

## 🔒 Security Best Practices

### 1. Disable SSH After Setup

```bash
# Option 1: Via Azure CLI
az network nsg rule delete \
  --resource-group $(terraform output -raw resource_group_name) \
  --nsg-name $(terraform output -raw network_security_group_id | cut -d'/' -f9) \
  --name SSH

# Option 2: Via Azure Portal
# Navigate to Network Security Group → Remove SSH rule
```

### 2. Regular Maintenance

```bash
# SSH to server for maintenance
ssh azureuser@YOUR_SERVER_IP

# Update system
sudo apt update && sudo apt upgrade -y

# Check WireGuard status
sudo systemctl status wg-quick@wg0
sudo wg show

# View logs
sudo journalctl -u wg-quick@wg0 -f
```

### 3. Client Management

The server includes a client management script:

```bash
# SSH to server
ssh azureuser@YOUR_SERVER_IP

# Use management script (requires sudo)
sudo ./manage-clients.sh list      # List current clients
sudo ./manage-clients.sh backup    # Backup configuration
```

## 📊 Monitoring and Troubleshooting

### Check Deployment Status

```bash
# View Terraform outputs
terraform output

# Check VM extension status
az vm extension list \
  --resource-group $(terraform output -raw resource_group_name) \
  --vm-name $(terraform output -raw virtual_machine_id | cut -d'/' -f9) \
  --output table
```

### Common Issues

#### 1. SSH Connection Refused
```bash
# Check if VM is running
az vm show \
  --resource-group $(terraform output -raw resource_group_name) \
  --name $(terraform output -raw virtual_machine_id | cut -d'/' -f9) \
  --show-details \
  --query powerState
```

#### 2. WireGuard Not Working
```bash
# SSH to server and check
ssh azureuser@YOUR_SERVER_IP

# Check WireGuard service
sudo systemctl status wg-quick@wg0

# Check installation log
sudo cat /var/log/wireguard-setup.log

# Restart WireGuard if needed
sudo systemctl restart wg-quick@wg0
```

#### 3. Client Connection Issues
- Verify client config has correct server IP
- Check firewall allows UDP traffic on WireGuard port
- Ensure client has internet connectivity
- Try different client DNS servers (8.8.8.8, 1.1.1.1)

## 💰 Cost Estimation

**Monthly costs (East US region):**
- VM Standard_B2s: ~$30-40/month
- Public IP: ~$3/month
- Storage: ~$5/month
- Bandwidth: Variable (first 5GB free)

**Total: ~$40-50/month** for basic setup

## 🧹 Cleanup

### Destroy All Resources

```bash
# Using deploy script
./deploy.sh cleanup

# Or manually
terraform destroy
```

### Partial Cleanup (Keep configs)

```bash
# Download configs first
scp azureuser@YOUR_SERVER_IP:/home/azureuser/wg0-client-*.conf ./

# Then destroy
terraform destroy
```

## 🔄 Updates and Modifications

### Change Client Count

1. Update `client_count` in `terraform.tfvars`
2. Run `terraform apply`
3. The script will generate additional clients

### Change VM Size

1. Update `vm_size` in `terraform.tfvars`
2. Run `terraform apply`
3. VM will be resized (requires restart)

### Update WireGuard Configuration

```bash
# SSH to server
ssh azureuser@YOUR_SERVER_IP

# Edit server config
sudo nano /etc/wireguard/wg0.conf

# Restart WireGuard
sudo systemctl restart wg-quick@wg0
```

## 📋 Terraform Outputs

After deployment, useful outputs include:

```bash
terraform output public_ip_address        # Server public IP
terraform output public_fqdn              # Server FQDN
terraform output ssh_connection_command   # SSH command
terraform output download_configs_command # Download command
terraform output wireguard_server_info   # Server configuration info
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📜 License

This project is based on [AzureWireGuard](https://github.com/vijayshinva/AzureWireGuard) and follows the same principles for quick WireGuard deployment on Azure.

## 🆘 Support

- Check the [troubleshooting section](#monitoring-and-troubleshooting)
- Review Azure VM extension logs
- Verify WireGuard service status on the server
- Ensure all prerequisites are met

---

**Happy VPNing! 🚀**# Azure WireGuard VPN Server - Terraform Deployment

This Terraform project deploys a WireGuard VPN server on Azure with automatic client configuration generation, based on the [AzureWireGuard](https://github.com/vijayshinva/AzureWireGuard) Bicep template.

## 🚀 Features

- **Automated WireGuard Installation**: Complete server setup with one Terraform apply
- **Multiple Client Configs**: Generates configurable number of client configurations (default: 10)
- **QR Codes**: Generates QR codes for easy mobile client setup
- **Security Hardened**: UFW firewall, iptables NAT rules, and proper key management
- **Azure Integration**: Uses Azure Network Security Groups and Public IP with FQDN
- **Scalable VM Sizes**: Supports multiple VM sizes with accelerated networking
- **Comprehensive Outputs**: Provides all necessary connection information

## 📋 Prerequisites

1. **Azure CLI** installed and authenticated
2. **Terraform** >= 1.0 installed
3. **SSH Key Pair** for VM access
4. **Azure Subscription** with sufficient permissions

## 🛠️ Quick Start

### 1. Clone and Setup

```bash
# Clone the repository (or download the files)
mkdir azure-wireguard-terraform
cd azure-wireguard-terraform

# Create the directory structure
mkdir -p scripts
```

### 2. Generate SSH Keys (if you don't have them)

```bash
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"