# --- infrastructure/outputs.tf ---

# Cluster B (AWS App)
output "cluster_b_public_ip" {
  description = "Public IP of Cluster B worker node"
  # FIXED: Uses the logical name 'aws_eks_2' seen in your logs
  value       = module.aws_eks_2.node_public_ip 
}

output "cluster_b_cluster_id" {
  description = "Cluster ID for AWS Cluster B"
  value       = module.aws_eks_2.cluster_id
}

# Cluster C (Azure App)
output "cluster_c_loadbalancer_dns" {
  description = "DNS name of the Load Balancer for Cluster C"
  # FIXED: Uses the logical name 'azure_aks_1' seen in your logs
  value       = module.azure_aks_1.load_balancer_dns
}

output "aks_resource_group" {
  description = "Azure Resource Group Name"
  value       = module.azure_aks_1.resource_group_name
}

output "aks_cluster_name" {
  description = "Azure AKS Cluster Name"
  value       = module.azure_aks_1.aks_cluster_name
}