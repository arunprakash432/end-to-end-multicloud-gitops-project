resource "azurerm_kubernetes_cluster" "aks" {
    name = var.cluster_name
    location = var.location
    resource_group_name = var.rg_name
    dns_prefix = var.cluster_name


    default_node_pool {
        name = "default"
        node_count = 1
        vm_size = "Standard_D4ds_v5"
        vnet_subnet_id = var.subnet_id
    }


    identity { type = "SystemAssigned" }
}