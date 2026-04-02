terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.10"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-3"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "harivelo-prod-v5"
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.30"
}

variable "db_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
  default     = "Harivelo2024StrongPass"
}

variable "instance_type" {
  description = "EC2 instance type for EKS nodes"
  type        = string
  default     = "t3.small"
}

variable "vpc_id" {
  description = "Existing VPC ID"
  type        = string
  default     = ""  # Sera rempli après import
}

variable "private_subnet_ids" {
  description = "Existing private subnet IDs"
  type        = list(string)
  default     = []  # Sera rempli après import
}

variable "public_subnet_ids" {
  description = "Existing public subnet IDs"
  type        = list(string)
  default     = []  # Sera rempli après import
}

# IAM Role pour EKS Cluster
resource "aws_iam_role" "eks_cluster" {
  name = "harivelo-eks-cluster-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "eks_cluster_vpc" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster.name
}

# IAM Role pour les nodes
resource "aws_iam_role" "eks_node" {
  name = "harivelo-eks-node-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_node" {
  count = 4
  policy_arn = element([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ], count.index)
  role = aws_iam_role.eks_node.name
}

# EKS Cluster (utiliser l'existant)
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids              = concat(var.public_subnet_ids, var.private_subnet_ids)
    endpoint_public_access  = true
    public_access_cidrs     = ["0.0.0.0/0"]
    security_group_ids      = [aws_security_group.eks.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster,
    aws_iam_role_policy_attachment.eks_cluster_vpc
  ]
}

# Security Group pour EKS
resource "aws_security_group" "eks" {
  name        = "harivelo-eks-sg"
  description = "Security group for EKS cluster"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "harivelo-eks-sg"
  }
}

# EKS Node Group
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "main-node-group"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = var.private_subnet_ids

  scaling_config {
    desired_size = 1
    max_size     = 3
    min_size     = 1
  }

  instance_types = [var.instance_type]

  update_config {
    max_unavailable = 1
  }

  tags = {
    "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
    "k8s.io/cluster-autoscaler/enabled"             = "true"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node,
    aws_eks_cluster.main
  ]
}

# Utiliser l'ECR existant
data "aws_ecr_repository" "app" {
  name = "harivelo-app"
}

# Utiliser le S3 bucket existant
data "aws_s3_bucket" "assets" {
  bucket = "harivelo-production-assets"
}

# Security Group pour RDS
resource "aws_security_group" "rds" {
  name        = "harivelo-rds-sg"
  description = "Security group for RDS"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.eks.id]
  }

  tags = {
    Name = "harivelo-rds-sg"
  }
}

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name        = "harivelo-rds-subnet-group"
  subnet_ids  = var.private_subnet_ids

  tags = {
    Name = "harivelo-rds-subnet-group"
  }
}

resource "aws_db_instance" "postgres" {
  identifier = "harivelo-production-postgres"

  engine         = "postgres"
  engine_version = "15.10"
  instance_class = "db.t3.micro"

  allocated_storage     = 20
  max_allocated_storage = 0

  db_name  = "harivelo_prod"
  username = "harivelo_admin"
  password = var.db_password
  port     = 5432

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name

  backup_retention_period = 0    # ← Free Tier : 0 obligatoire
  skip_final_snapshot     = true
  deletion_protection     = false
  publicly_accessible     = false

  
  # backup_window      = "03:00-04:00"
  # maintenance_window = "sun:04:00-sun:05:00"

  tags = {
    Environment = var.environment
  }
}

# Outputs
output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "ecr_repository_url" {
  value = data.aws_ecr_repository.app.repository_url
}

output "rds_endpoint" {
  value = aws_db_instance.postgres.endpoint
  sensitive = true
}

output "s3_bucket_name" {
  value = data.aws_s3_bucket.assets.id
}

output "kubectl_config" {
  value = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}
