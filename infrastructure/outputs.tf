# --- infrastructure/outputs.tf ---

# Cluster B (AWS App)
output "cluster_b_public_ip" {
  description = "Public IP of Cluster B worker node"
  # FIXED: Matches 'module.aws_eks_2' from Log 30
  value       = module.aws_eks_2.node_public_ip 
}

output "cluster_b_cluster_id" {
  value = module.aws_eks_2.cluster_id
}

# Cluster C (Azure App)
output "cluster_c_loadbalancer_dns" {
  description = "DNS name of the Load Balancer for Cluster C"
  # FIXED: Matches 'module.azure_aks_1' from Log 30
  value       = module.azure_aks_1.load_balancer_dns
}

output "aks_resource_group" {
  value = module.azure_aks_1.resource_group_name
}

output "aks_cluster_name" {
  value = module.azure_aks_1.aks_cluster_name
}