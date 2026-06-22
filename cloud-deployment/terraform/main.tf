# Terraform configuration for System Maintenance deployment
# Supports multiple cloud providers

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    azure = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}

# Provider selection based on environment
provider "aws" {
  region = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
  client_id       = var.azure_client_id
  client_secret   = var.azure_client_secret
  tenant_id       = var.azure_tenant_id
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
  credentials = var.gcp_credentials
}

# Variables
variable "deployment_target" {
  description = "Target cloud provider (aws, azure, gcp)"
  type        = string
  default     = "aws"
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "azure_location" {
  description = "Azure region for deployment"
  type        = string
  default     = "eastus"
}

variable "gcp_region" {
  description = "GCP region for deployment"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "instance_count" {
  description = "Number of instances to deploy"
  type        = number
  default     = 2
}

# Local variables
locals {
  project_name = "system-maintenance"
  common_tags = {
    Project     = local.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Data sources
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# AWS Resources (conditional)
resource "aws_vpc" "main" {
  count = var.deployment_target == "aws" ? 1 : 0
  
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = merge(local.common_tags, {
    Name = "${local.project_name}-vpc"
  })
}

resource "aws_subnet" "public" {
  count = var.deployment_target == "aws" ? 2 : 0
  
  vpc_id                  = aws_vpc.main[0].id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  
  tags = merge(local.common_tags, {
    Name = "${local.project_name}-public-subnet-${count.index + 1}"
  })
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_internet_gateway" "main" {
  count = var.deployment_target == "aws" ? 1 : 0
  
  vpc_id = aws_vpc.main[0].id
  
  tags = merge(local.common_tags, {
    Name = "${local.project_name}-igw"
  })
}

resource "aws_route_table" "public" {
  count = var.deployment_target == "aws" ? 1 : 0
  
  vpc_id = aws_vpc.main[0].id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main[0].id
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.project_name}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count = var.deployment_target == "aws" ? 2 : 0
  
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_security_group" "main" {
  count = var.deployment_target == "aws" ? 1 : 0
  
  name_prefix = "${local.project_name}-"
  vpc_id      = aws_vpc.main[0].id
  
  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # HTTP access for monitoring
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # Grafana dashboard
  ingress {
    from_port   = 3002
    to_port     = 3002
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # Prometheus
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # Custom web dashboard
  ingress {
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.project_name}-sg"
  })
}

resource "aws_instance" "maintenance_server" {
  count = var.deployment_target == "aws" ? var.instance_count : 0
  
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.deployment_target == "aws" ? var.aws_instance_type : "t3.micro"
  subnet_id     = aws_subnet.public[count.index % 2].id
  
  vpc_security_group_ids = [aws_security_group.main[0].id]
  
  user_data = templatefile("${path.module}/user-data.sh", {
    environment = var.environment
    project_name = local.project_name
  })
  
  tags = merge(local.common_tags, {
    Name = "${local.project_name}-server-${count.index + 1}"
  })
}

resource "aws_eip" "maintenance" {
  count = var.deployment_target == "aws" ? var.instance_count : 0
  
  instance = aws_instance.maintenance_server[count.index].id
  domain   = "vpc"
  
  tags = merge(local.common_tags, {
    Name = "${local.project_name}-eip-${count.index + 1}"
  })
}

variable "aws_instance_type" {
  description = "AWS instance type"
  type        = string
  default     = "t3.micro"
}

# Outputs
output "aws_instance_ips" {
  value = var.deployment_target == "aws" ? aws_eip.maintenance[*].public_ip : []
  description = "Public IPs of AWS instances"
}

output "aws_vpc_id" {
  value = var.deployment_target == "aws" ? aws_vpc.main[0].id : ""
  description = "VPC ID"
}
