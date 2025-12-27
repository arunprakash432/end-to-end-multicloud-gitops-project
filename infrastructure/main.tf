module "aws_vpc_1" {
    source = "./modules/cluster-a-monitoring/aws-vpc-1"
    name = "eks-vpc-monitoring-1"
    cidr = "10.0.0.0/16"
}


module "aws_eks_1" {
    source = "./modules/cluster-a-monitoring/aws-eks-1"
    cluster_name = "eks-cluster-monitoring-1"
    vpc_id = module.aws_vpc_1.vpc_id
    private_subnets = module.aws_vpc_1.private_subnets
}


module "aws_vpc_2" {
    source = "./modules/cluster-b-app/aws-vpc-2"
    name = "aws-app-vpc-2"
    cidr = "10.1.0.0/16"
}


module "aws_eks_2" {
    source = "./modules/cluster-b-app/aws-eks-2"
    cluster_name = "aws-app-vpc-2"
    vpc_id = module.aws_vpc_2.vpc_id
    private_subnets = module.aws_vpc_2.private_subnets
}


module "azure_vnet_1" {
    source = "./modules/cluster-c-app/azure-vnet-1"
    name = "azure-app-vnet-1"
    location = var.azure_location
}


module "azure_aks_1" {
    source = "./modules/cluster-c-app/azure-aks-1"
    cluster_name = "azure-app-aks-1"
    location = var.azure_location
    subnet_id = module.azure_vnet_1.subnet_id
    rg_name = module.azure_vnet_1.rg_name
}

