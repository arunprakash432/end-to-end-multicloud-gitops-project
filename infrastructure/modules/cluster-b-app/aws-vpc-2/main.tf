resource "aws_vpc" "this" {
    cidr_block = var.cidr
    enable_dns_support = true
    enable_dns_hostnames = true
    tags = { Name = var.name }
}


resource "aws_internet_gateway" "igw" {
    vpc_id = aws_vpc.this.id
}


resource "aws_subnet" "public" {
    count = 2
    vpc_id = aws_vpc.this.id
    cidr_block = cidrsubnet(var.cidr, 8, count.index)
    availability_zone = "ap-south-1${count.index == 0 ? "a" : "b"}"
    map_public_ip_on_launch = true
}

resource "aws_subnet" "private" {
    count = 2
    vpc_id = aws_vpc.this.id
    cidr_block = cidrsubnet(var.cidr, 8, count.index + 10)
    availability_zone = "ap-south-1${count.index == 0 ? "a" : "b"}"
}


resource "aws_eip" "nat" { domain = "vpc" }


resource "aws_nat_gateway" "nat" {
    allocation_id = aws_eip.nat.id
    subnet_id = aws_subnet.public[0].id
}


resource "aws_route_table" "public" {
    vpc_id = aws_vpc.this.id
    route { 
        
        cidr_block = "0.0.0.0/0" 
        gateway_id = aws_internet_gateway.igw.id 
        
        }
}


resource "aws_route_table" "private" {
    vpc_id = aws_vpc.this.id
    route { 

        cidr_block = "0.0.0.0/0" 
        nat_gateway_id = aws_nat_gateway.nat.id
        
         }
}


resource "aws_route_table_association" "public" {
    count = 2
    subnet_id = aws_subnet.public[count.index].id
    route_table_id = aws_route_table.public.id
}


resource "aws_route_table_association" "private" {
    count = 2
    subnet_id = aws_subnet.private[count.index].id
    route_table_id = aws_route_table.private.id
}