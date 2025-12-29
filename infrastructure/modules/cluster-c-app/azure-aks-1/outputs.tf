output "endpoint" { 
    value = azurerm_kubernetes_cluster.aks.kube_config[0].host
}

output "cluster_name" {
  value = azurerm_kubernetes_cluster.aks.name
}