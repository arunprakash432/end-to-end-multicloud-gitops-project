output "endpoint" { 
    value = azurerm_kubernetes_cluster.aks.kube_config[0].host
}