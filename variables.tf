variable "location" {
  description = "The Azure Region in which all resources should be created"
  type        = string
  default     = "East US"
}

variable "admin_username" {
  description = "The admin username for the Virtual Machine"
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key" {
  description = "The SSH public key for VM access"
  type        = string
  validation {
    condition     = can(regex("^ssh-", var.ssh_public_key))
    error_message = "The ssh_public_key must be a valid SSH public key."
  }
}

variable "vm_size" {
  description = "The size of the Virtual Machine"
  type        = string
  default     = "Standard_B2s"

  validation {
    condition = contains([
      "Standard_B1s", "Standard_B2s", "Standard_B1ms", "Standard_B2ms",
      "Standard_DS1_v2", "Standard_DS2_v2", "Standard_D2s_v3"
    ], var.vm_size)
    error_message = "VM size must be one of the supported sizes."
  }
}

variable "wireguard_port" {
  description = "The port WireGuard will listen on"
  type        = number
  default     = 51820

  validation {
    condition     = var.wireguard_port > 1024 && var.wireguard_port < 65535
    error_message = "WireGuard port must be between 1025 and 65534."
  }
}

variable "wireguard_subnet" {
  description = "The subnet used for WireGuard VPN clients"
  type        = string
  default     = "10.13.13.0/24"

  validation {
    condition     = can(cidrhost(var.wireguard_subnet, 0))
    error_message = "The wireguard_subnet must be a valid CIDR notation."
  }
}

variable "client_count" {
  description = "Number of WireGuard client configurations to generate"
  type        = number
  default     = 10

  validation {
    condition     = var.client_count >= 1 && var.client_count <= 50
    error_message = "Client count must be between 1 and 50."
  }
}

variable "client_dns" {
  description = "DNS server to use for WireGuard clients"
  type        = string
  default     = "1.1.1.1"

  validation {
    condition     = can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", var.client_dns))
    error_message = "Client DNS must be a valid IP address."
  }
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default = {
    Environment  = "Production"
    Project      = "WireGuard-VPN"
    ManagedBy    = "Terraform"
    DeployedDate = ""
  }
}