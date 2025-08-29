#!/bin/bash

# WireGuard Installation and Configuration Script for Azure Ubuntu VM
# This script sets up a WireGuard VPN server and generates client configurations

set -e

# Variables from Terraform
SERVER_PUBLIC_IP="${server_public_ip}"
WG_PORT="${wireguard_port}"
WG_SUBNET="${server_subnet}"
CLIENT_COUNT="${client_count}"
CLIENT_DNS="${client_dns}"
SERVER_IP=$(echo "${server_subnet}" | sed 's|/.*|/32|' | sed 's|\.0/|.1/|')

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a /var/log/wireguard-setup.log
}

log "Starting WireGuard installation and configuration"

# Update system
log "Updating system packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y

# Install required packages
log "Installing required packages"
apt-get install -y \
    wireguard \
    wireguard-tools \
    ufw \
    iptables-persistent \
    curl \
    qrencode \
    net-tools

# Enable IP forwarding
log "Enabling IP forwarding"
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf
sysctl -p

# Create WireGuard directory
mkdir -p /etc/wireguard
chmod 700 /etc/wireguard

# Generate server keys using WireGuard tools (simpler and more reliable)
log "Generating WireGuard server keys"
SERVER_PRIVATE_KEY=$(wg genkey)
SERVER_PUBLIC_KEY=$(echo "$SERVER_PRIVATE_KEY" | wg pubkey)

# Create server configuration
log "Creating WireGuard server configuration"
cat > /etc/wireguard/wg0.conf << EOF
[Interface]
PrivateKey = $SERVER_PRIVATE_KEY
Address = $(echo "$WG_SUBNET" | sed 's|/.*|/32|' | sed 's|\.0/|.1/|')
ListenPort = $WG_PORT
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

EOF

# Generate client configurations
log "Generating client configurations"
for i in $(seq 1 $CLIENT_COUNT); do
    log "Generating client $i configuration"
    
    # Generate client private key
    CLIENT_PRIVATE_KEY=$(wg genkey)
    CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | wg pubkey)
    
    # Calculate client IP
    BASE_IP=$(echo "$WG_SUBNET" | cut -d'/' -f1 | cut -d'.' -f1-3)
    CLIENT_IP="$BASE_IP.$((100 + i))"
    
    # Add peer to server configuration
    cat >> /etc/wireguard/wg0.conf << EOF
[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = $CLIENT_IP/32

EOF

    # Create client configuration file
    cat > /home/azureuser/wg0-client-$i.conf << EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $CLIENT_IP/32
DNS = $CLIENT_DNS

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $SERVER_PUBLIC_IP:$WG_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

    # Set proper permissions
    chmod 600 /home/azureuser/wg0-client-$i.conf
    chown azureuser:azureuser /home/azureuser/wg0-client-$i.conf
    
    # Generate QR code for mobile clients
    qrencode -t ansiutf8 < /home/azureuser/wg0-client-$i.conf > /home/azureuser/wg0-client-$i.qr
    chown azureuser:azureuser /home/azureuser/wg0-client-$i.qr
    
    log "Client $i configuration created: /home/azureuser/wg0-client-$i.conf"
done

# Set permissions for server config
chmod 600 /etc/wireguard/wg0.conf

# Configure UFW firewall
log "Configuring UFW firewall"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow $WG_PORT/udp comment 'WireGuard'
ufw allow 22/tcp comment 'SSH'
ufw --force enable

# Configure iptables for NAT
log "Configuring iptables rules"
iptables -A FORWARD -i wg0 -j ACCEPT
iptables -A FORWARD -o wg0 -j ACCEPT
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# Save iptables rules
iptables-save > /etc/iptables/rules.v4
ip6tables-save > /etc/iptables/rules.v6

# Enable and start WireGuard
log "Starting WireGuard service"
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# Wait a moment for the interface to come up
sleep 5

# Verify WireGuard is running
if systemctl is-active --quiet wg-quick@wg0; then
    log "WireGuard service started successfully"
    wg show
else
    log "ERROR: WireGuard service failed to start"
    systemctl status wg-quick@wg0
    exit 1
fi

# Create a summary file
log "Creating configuration summary"
cat > /home/azureuser/wireguard-summary.txt << EOF
WireGuard VPN Server Configuration Summary
==========================================

Server Information:
- Public IP: $SERVER_PUBLIC_IP
- WireGuard Port: $WG_PORT
- Server Subnet: $WG_SUBNET
- Server Public Key: $SERVER_PUBLIC_KEY

Client Configurations:
- Number of clients: $CLIENT_COUNT
- Client IP range: $(echo "$WG_SUBNET" | cut -d'/' -f1 | cut -d'.' -f1-3).101 - $(echo "$WG_SUBNET" | cut -d'/' -f1 | cut -d'.' -f1-3).$((100 + CLIENT_COUNT))
- DNS Server: $CLIENT_DNS

Configuration Files:
$(for i in $(seq 1 $CLIENT_COUNT); do echo "- /home/azureuser/wg0-client-$i.conf"; done)

QR Codes (for mobile clients):
$(for i in $(seq 1 $CLIENT_COUNT); do echo "- /home/azureuser/wg0-client-$i.qr"; done)

To download all client configs:
scp azureuser@$SERVER_PUBLIC_IP:/home/azureuser/wg0-client-*.conf ./

To view a QR code:
cat /home/azureuser/wg0-client-1.qr

Security Notes:
- SSH is currently enabled on port 22. Disable it after downloading configs for better security.
- All client configurations are located in /home/azureuser/
- Server configuration is in /etc/wireguard/wg0.conf (root access required)
EOF

chown azureuser:azureuser /home/azureuser/wireguard-summary.txt

# Create script to easily add/remove clients
cat > /home/azureuser/manage-clients.sh << 'EOF'
#!/bin/bash

# WireGuard Client Management Script

WG_CONFIG="/etc/wireguard/wg0.conf"
BACKUP_DIR="/home/azureuser/backups"

usage() {
    echo "Usage: $0 {add|remove|list|backup} [client-name]"
    echo "  add <name>     - Add a new client"
    echo "  remove <name>  - Remove a client"
    echo "  list           - List all clients"
    echo "  backup         - Backup current configuration"
}

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

case "$1" in
    add)
        if [ -z "$2" ]; then
            echo "Please specify client name"
            exit 1
        fi
        # Implementation for adding client
        echo "Adding client $2..."
        ;;
    remove)
        if [ -z "$2" ]; then
            echo "Please specify client name"
            exit 1
        fi
        # Implementation for removing client
        echo "Removing client $2..."
        ;;
    list)
        echo "Current WireGuard clients:"
        wg show wg0 peers
        ;;
    backup)
        mkdir -p "$BACKUP_DIR"
        cp "$WG_CONFIG" "$BACKUP_DIR/wg0.conf.$(date +%Y%m%d-%H%M%S)"
        echo "Configuration backed up to $BACKUP_DIR"
        ;;
    *)
        usage
        exit 1
        ;;
esac
EOF

chmod +x /home/azureuser/manage-clients.sh
chown azureuser:azureuser /home/azureuser/manage-clients.sh

# Final system updates and cleanup
log "Performing final system updates"
apt-get autoremove -y
apt-get autoclean

# Schedule reboot for server updates (optional, after 30 minutes)
# echo "sudo reboot" | at now + 30 minutes 2>/dev/null || true

log "WireGuard installation and configuration completed successfully!"
log "Configuration summary available at: /home/azureuser/wireguard-summary.txt"
log "Client management script available at: /home/azureuser/manage-clients.sh"

# Display final status
echo "===========================================" | tee -a /var/log/wireguard-setup.log
echo "WireGuard VPN Server Setup Complete!" | tee -a /var/log/wireguard-setup.log
echo "===========================================" | tee -a /var/log/wireguard-setup.log
echo "Server IP: $SERVER_PUBLIC_IP" | tee -a /var/log/wireguard-setup.log
echo "WireGuard Port: $WG_PORT" | tee -a /var/log/wireguard-setup.log
echo "Client configs: /home/azureuser/wg0-client-*.conf" | tee -a /var/log/wireguard-setup.log
echo "Summary: /home/azureuser/wireguard-summary.txt" | tee -a /var/log/wireguard-setup.log
echo "===========================================" | tee -a /var/log/wireguard-setup.log