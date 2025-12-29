# --- infrastructure/outputs.tf ---

# Cluster B (AWS App)
output "cluster_b_public_ip" {
  description = "Public IP of Cluster B worker node"
  # FIXED: Changed 'module.cluster-b-app' to 'module.aws_eks_2'
  value       = module.aws_eks_2.node_public_ip 
}

output "cluster_b_cluster_id" {
  description = "Cluster ID for AWS Cluster B"
  # FIXED: Changed 'module.aws_eks_cluster_b' to 'module.aws_eks_2'
  value       = module.aws_eks_2.cluster_id
}

# Cluster C (Azure App)
output "cluster_c_loadbalancer_dns" {
  description = "DNS name of the Load Balancer for Cluster C"
  # FIXED: Changed 'module.cluster-c-app' to 'module.azure_aks_1'
  value       = module.azure_aks_1.load_balancer_dns
}

output "aks_resource_group" {
  description = "Azure Resource Group Name"
  # FIXED: Changed 'module.aks_cluster' to 'module.azure_aks_1'
  value       = module.azure_aks_1.resource_group_name
}

output "aks_cluster_name" {
  description = "Azure AKS Cluster Name"
  # FIXED: Changed 'module.aks_cluster' to 'module.azure_aks_1'
  value       = module.azure_aks_1.aks_cluster_name
}