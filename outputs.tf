output "resource_group_name" {
  description = "The name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "public_ip_address" {
  description = "The public IP address of the WireGuard server"
  value       = azurerm_public_ip.main.ip_address
}

output "public_fqdn" {
  description = "The public FQDN of the WireGuard server"
  value       = azurerm_public_ip.main.fqdn
}

output "ssh_connection_command" {
  description = "SSH command to connect to the server"
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.main.ip_address}"
}

output "wireguard_server_info" {
  description = "WireGuard server configuration information"
  value = {
    port           = var.wireguard_port
    subnet         = var.wireguard_subnet
    client_count   = var.client_count
    server_ip      = cidrhost(var.wireguard_subnet, 1)
  }
}

output "server_public_key" {
  description = "The WireGuard server's public key (available after deployment in /home/azureuser/wireguard-summary.txt)"
  value       = "Check /home/azureuser/wireguard-summary.txt on the server after deployment"
  sensitive   = false
}

output "download_configs_command" {
  description = "Command to download all client configuration files"
  value       = "scp ${var.admin_username}@${azurerm_public_ip.main.ip_address}:/home/${var.admin_username}/wg0-client-*.conf ./"
}

output "client_config_locations" {
  description = "Locations of client configuration files on the server"
  value = [
    for i in range(var.client_count) : "/home/${var.admin_username}/wg0-client-${i + 1}.conf"
  ]
}

output "network_security_group_id" {
  description = "The ID of the Network Security Group"
  value       = azurerm_network_security_group.main.id
}

output "virtual_machine_id" {
  description = "The ID of the Virtual Machine"
  value       = azurerm_linux_virtual_machine.main.id
}