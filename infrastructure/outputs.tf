# Cluster B (AWS App)
output "cluster_b_public_ip" {
  description = "Public IP of Cluster B worker node"
  value       = module.cluster-b-app.node_public_ip 
}

output "cluster_b_cluster_id" {
  value = module.aws_eks_cluster_b.cluster_id
}

# Cluster C (Azure App)
output "cluster_c_loadbalancer_dns" {
  description = "DNS name of the Load Balancer for Cluster C"
  value       = module.cluster-c-app.load_balancer_dns
}

output "aks_resource_group" {
  value = module.aks_cluster.resource_group_name
}

output "aks_cluster_name" {
  value = module.aks_cluster.aks_cluster_name
}