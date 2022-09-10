terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.30.0"
    }
  }
}

provider "aws" {
  region                  = "us-east-1"
  shared_credentials_file = "~/.aws/credentials"
  profile                 = "default"
}

# Create a Custom VPC
resource "aws_vpc" "wk18-vpc" {
    cidr_block = "10.0.0.0/16"
    enable_dns_hostnames = true
    enable_dns_support = true   
    instance_tenancy = "default"

    tags = {
        Name = "week18-vpc"
    }
}

# Create Public and Private Subnet in 1 AZ
resource "aws_subnet" "week18_public_subnet1" {
    tags = {
        Name = "public_subnet1"
    }
    vpc_id = aws_vpc.wk18-vpc.id
    cidr_block = "10.0.1.0/24"
    map_public_ip_on_launch = true
    availability_zone = "us-east-1a"
}

resource "aws_subnet" "week18_private_subnet1" {
    tags = {
        Name = "private_subnet1"
    }
    vpc_id = aws_vpc.wk18-vpc.id
    cidr_block = "10.0.3.0/24"
    map_public_ip_on_launch = false
    availability_zone = "us-east-1a"
}

# Create Another Public and Private Subnet in a separate AZ
resource "aws_subnet" "week18_public_subnet2" {
    tags = {
        Name = "public_subnet2"
    }
    vpc_id = aws_vpc.wk18-vpc.id
    cidr_block = "10.0.2.0/24"
    map_public_ip_on_launch = true
    availability_zone = "us-east-1b"
}

resource "aws_subnet" "week18_private_subnet2" {
    tags = {
        Name = "private_subnet2"
    }
    vpc_id = aws_vpc.wk18-vpc.id
    cidr_block = "10.0.4.0/24"
    map_public_ip_on_launch = false
    availability_zone = "us-east-1b"
}

# Create an Internet Gateway
resource "aws_internet_gateway" "week18_internet_gateway" {
    vpc_id = aws_vpc.wk18-vpc.id

    tags = {
        Name = "week18-igw"
    }
}

# Create a Main Public Routing Table
resource "aws_route_table" "wk18-public-rt" {
    vpc_id = aws_vpc.wk18-vpc.id

    tags = {
        Name = "week18-public-rt"
    }
}

# Create a default public route
resource "aws_route" "default_public_route" {
    route_table_id = aws_route_table.wk18-public-rt.id
    destination_cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.week18_internet_gateway.id
}

# Create public route table associations
resource "aws_route_table_association" "wk18-public-association1" {
    subnet_id = aws_subnet.week18_public_subnet1.id
    route_table_id = aws_route_table.wk18-public-rt.id 
}

resource "aws_route_table_association" "wk18-public-association2" {
    subnet_id = aws_subnet.week18_public_subnet2.id
    route_table_id = aws_route_table.wk18-public-rt.id 
}

# Create a security group for our EC2 Instances and our Database Instance
# EC2 Instance Security Group
resource "aws_security_group" "wk18-ec2-sg" {
    name = "week18-ec2-security-group"
    description = "access for ec2 instances"
    vpc_id = aws_vpc.wk18-vpc.id

    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["174.57.67.44/32"]
    }

    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

# Create a database subnet for our RDS Instance
resource "aws_db_subnet_group" "db_subnet"  {
    name       = "db_subnet"
    subnet_ids = [aws_subnet.week18_private_subnet1.id, aws_subnet.week18_private_subnet2.id]
}

# Database Instance Security Group
resource "aws_security_group" "wk18-db-sg" {
    name = "week18-database-security-group"
    description = "access for database rds instance"
    vpc_id = aws_vpc.wk18-vpc.id

    ingress {
        from_port = 3306
        to_port = 3306
        protocol = "tcp"
        security_groups = [aws_security_group.wk18-ec2-sg.id]
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        security_groups = [aws_security_group.wk18-ec2-sg.id]
        cidr_blocks = ["10.0.0.0/16"]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

# Create a Load Balancer to shift traffic between the public subnets for our EC2 Instances
resource "aws_alb" "wk18-alb" {
    name = "week18-ec2-load-balancer"
    load_balancer_type = "application"
    internal = false
    subnets = [aws_subnet.week18_public_subnet1.id, aws_subnet.week18_public_subnet2.id]
    security_groups = [aws_security_group.wk18-ec2-sg.id]
}

# Launch our two EC2 Instances into our public subnets, 1 in each
# EC2 Instance getting launched into public subnet 1
resource "aws_instance" "week18-ec2-instance1" {
    ami = "ami-05fa00d4c63e32376"
    subnet_id = aws_subnet.week18_public_subnet1.id
    instance_type = "t2.micro"
    security_groups = [aws_security_group.wk18-ec2-sg.id]
}

# EC2 Instance getting launched into public subnet 2
resource "aws_instance" "week18-ec2-instance2" {
    ami = "ami-05fa00d4c63e32376"
    subnet_id = aws_subnet.week18_public_subnet2.id
    instance_type = "t2.micro"
    security_groups = [aws_security_group.wk18-ec2-sg.id]
}

# Launch an RDS MySQL Instance into a private subnet
resource "aws_db_instance" "database1" {
    allocated_storage    = 5
    engine               = "mysql"
    engine_version       = "5.7"
    instance_class       = "db.t3.micro"
    db_subnet_group_name = "db_subnet"
    vpc_security_group_ids = [aws_security_group.wk18-db-sg.id]
    username             = "admin"
    password             = "password"
    skip_final_snapshot  = true
}