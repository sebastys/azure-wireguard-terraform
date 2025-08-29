# Create a random string for unique resource names
resource "random_string" "unique" {
  length  = 8
  special = false
  upper   = false
}

# Create a resource group
resource "azurerm_resource_group" "main" {
  name     = "rg-wireguard-${random_string.unique.result}"
  location = var.location

  tags = var.tags
}

# Create a virtual network
resource "azurerm_virtual_network" "main" {
  name                = "vnet-wireguard-${random_string.unique.result}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = var.tags
}

# Create a subnet
resource "azurerm_subnet" "internal" {
  name                 = "snet-wireguard-${random_string.unique.result}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]
}

# Create public IP
resource "azurerm_public_ip" "main" {
  name                = "pip-wireguard-${random_string.unique.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
  domain_name_label   = "wireguard-${random_string.unique.result}"

  tags = var.tags
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "main" {
  name                = "nsg-wireguard-${random_string.unique.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # WireGuard port
  security_rule {
    name                       = "WireGuard"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = var.wireguard_port
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # SSH port (disable after setup for security)
  security_rule {
    name                       = "SSH"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = var.tags
}

# Create network interface
resource "azurerm_network_interface" "main" {
  name                = "nic-wireguard-${random_string.unique.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  accelerated_networking_enabled = true

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.internal.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }

  tags = var.tags
}

# Associate Network Security Group to the network interface
resource "azurerm_network_interface_security_group_association" "main" {
  depends_on                = [azurerm_network_security_group.main]
  network_interface_id      = azurerm_network_interface.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}

# Create virtual machine
resource "azurerm_linux_virtual_machine" "main" {
  name                = "vm-wireguard-${random_string.unique.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = var.vm_size
  admin_username      = var.admin_username

  # Disable password authentication
  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.main.id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  tags = var.tags
}

# Install and configure WireGuard
resource "azurerm_virtual_machine_extension" "wireguard_setup" {
  name                 = "wireguard-setup"
  virtual_machine_id   = azurerm_linux_virtual_machine.main.id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.1"

  protected_settings = jsonencode({
    "script" = base64encode(templatefile("${path.module}/scripts/install_wireguard.sh", {
      server_public_ip = azurerm_public_ip.main.ip_address
      wireguard_port   = var.wireguard_port
      server_subnet    = var.wireguard_subnet
      client_count     = var.client_count
      client_dns       = var.client_dns
    }))
  })

  depends_on = [azurerm_network_interface_security_group_association.main]

  tags = var.tags
}