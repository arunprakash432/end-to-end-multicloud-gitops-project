output "eks1_endpoint" { 
    value = module.aws_eks_1.endpoint
}

output "eks2_endpoint" { 
    value = module.aws_eks_2.endpoint
}

output "aks_endpoint" { 
    value = module.azure_aks_1.endpoint 
    sensitive=true
}


