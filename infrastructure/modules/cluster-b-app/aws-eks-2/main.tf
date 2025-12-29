resource "aws_iam_role" "cluster" {
    assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "eks.amazonaws.com" }, Action = "sts:AssumeRole" }]
    })
}


resource "aws_iam_role_policy_attachment" "cluster" {
    role = aws_iam_role.cluster.name
    policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}


resource "aws_iam_role" "node" {
    assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
    })
}


resource "aws_iam_role_policy_attachment" "node" {
    for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
    ])
    role = aws_iam_role.node.name
    policy_arn = each.value
}


resource "aws_eks_cluster" "this" {
    name = var.cluster_name
    role_arn = aws_iam_role.cluster.arn


    vpc_config {
         subnet_ids = var.private_subnets
     }
}



resource "aws_eks_node_group" "ng" {
    cluster_name = aws_eks_cluster.this.name
    node_role_arn = aws_iam_role.node.arn
    subnet_ids = var.private_subnets


    scaling_config { 
        
        desired_size = 2 
        max_size = 2 
        min_size = 1 
        
        }


    instance_types = ["c7i-flex.large"]
}