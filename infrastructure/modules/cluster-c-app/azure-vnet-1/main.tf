resource "azurerm_resource_group" "rg" {
name = "rg-${var.name}"
location = var.location
}


resource "azurerm_virtual_network" "vnet" {
name = var.name
location = var.location
resource_group_name = azurerm_resource_group.rg.name
address_space = ["10.2.0.0/16"]
}


resource "azurerm_subnet" "subnet" {
name = "aks-subnet"
resource_group_name = azurerm_resource_group.rg.name
virtual_network_name = azurerm_virtual_network.vnet.name
address_prefixes = ["10.2.1.0/24"]
}