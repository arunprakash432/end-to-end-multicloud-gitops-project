terraform {
    backend "s3" {
        bucket = "multicloud-backend-bucket-12345"
        key = "prod/terraform.tfstate"
        region = "ap-south-1"
        dynamodb_table = "terraform-eks-state-locks-1"
        encrypt = true
    }
}