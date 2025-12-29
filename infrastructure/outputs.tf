output "eks2_endpoint" {
  value = module.aws_eks_2.cluster_endpoint
}

output "aks_endpoint" {
  value = module.azure_aks_1.kube_config[0].host
}

output "resource_group_name" {
  value = module.azure_vnet_1.resource_group_name
}

output "aks_cluster_name" {
  value = module.azure_aks_1.aks_cluster_name
}
