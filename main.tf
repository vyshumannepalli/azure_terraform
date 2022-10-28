provider "azurerm" {
  features {}
}


resource "azurerm_resource_group" "rg" {
  location = var.resource_group_location
  name     = "south-india-rg"
}

resource "azurerm_virtual_network" "vn" {
  name                = "vpc"
  location            = var.resource_group_location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = [var.vpc_cidr]
  tags = {
    environment = "Dev"
  }
}

resource "azurerm_subnet" "private_subnets" {
  name                 = "private-subnet-${count.index}"
  count                = 2
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vn.name
  address_prefixes     = [cidrsubnet(var.vpc_cidr, 4, count.index)]
}

resource "azurerm_subnet" "public_subnets" {
  name                 = "public-subnet-${count.index}"
  count                = 2
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vn.name
  address_prefixes     = [cidrsubnet(var.vpc_cidr, 4, (count.index + 2))]
}

resource "azurerm_route_table" "public_rt" {
  name                          = "public-route-table"
  location                      = var.resource_group_location
  resource_group_name           = azurerm_resource_group.rg.name
  disable_bgp_route_propagation = false

  route {
    name           = "internet-route"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "Internet"
  }

  tags = {
    environment = "Dev"
  }
}

resource "azurerm_subnet_route_table_association" "public_rt_assc" {
  count          = 2
  subnet_id      = element(azurerm_subnet.public_subnets.*.id, (count.index + 2))
  route_table_id = azurerm_route_table.public_rt.id
}

resource "azurerm_network_security_group" "nsg_public" {
  name                = "public_sg"
  location            = var.resource_group_location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "http"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    environment = "Dev"
  }
}

resource "azurerm_subnet_network_security_group_association" "sg_assoc" {
  count                     = 2
  subnet_id                 = element(azurerm_subnet.public_subnets.*.id, (count.index + 2))
  network_security_group_id = azurerm_network_security_group.nsg_public.id
}

resource "azurerm_public_ip" "vm_ip" {
  name                = "vm_ip"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.resource_group_location
  allocation_method   = "Static"

  tags = {
    environment = "Dev"
  }
}

resource "azurerm_network_interface" "nic" {
  name                = "test-nic"
  location            = var.resource_group_location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "public"
    subnet_id                     = azurerm_subnet.public_subnets[0].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm_ip.id
  }
}

resource "azurerm_network_interface_security_group_association" "nsg_nic" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg_public.id
}

resource "azurerm_linux_virtual_machine" "vm" {
  name                  = "test-vm"
  location              = var.resource_group_location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.nic.id]
  size                  = "Standard_DS1_v2"
  admin_username        = "azureuser"

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  admin_ssh_key {
    username   = "azureuser"
    public_key = file("~/.ssh/id_rsa.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  custom_data = filebase64("scripts/wordpress.sh")
  tags = {
    environment = "Dev"
  }
}

resource "azurerm_storage_account" "my_storage_ac" {
  name                     = "vyshustorageac"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = var.resource_group_location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = {
    environment = "Dev"
  }
}

resource "azurerm_mysql_server" "wordpress" {
  name                         = "wp-sqlserver"
  location                     = var.resource_group_location
  resource_group_name          = azurerm_resource_group.rg.name
  administrator_login          = "Vyshu-Test"
  administrator_login_password = "05c806a1-499b-41fa-abfb-08df8dacf9d9"


  sku_name   = "GP_Gen5_2"
  storage_mb = 5120
  version    = "5.7"

  ssl_enforcement_enabled = true
}


resource "azurerm_mysql_database" "wordpress" {
  name                = "wp-db"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_mysql_server.wordpress.name
  charset             = "utf8"
  collation           = "utf8_unicode_ci"
}

resource "azurerm_mysql_firewall_rule" "azure" {
  name                = "public-internet"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_mysql_server.wordpress.name
  start_ip_address    = azurerm_public_ip.vm_ip.ip_address
  end_ip_address      = azurerm_public_ip.vm_ip.ip_address
}

