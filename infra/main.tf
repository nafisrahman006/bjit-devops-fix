# Using AWS default VPC to keep it simple for this assessment

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# ---------------------------------------------------------------------------
# EC2 Instance (the API server)

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_instance" "api" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"  # was m5.4xlarge (way too big/expensive)

  root_block_device {
    volume_type = "gp3"       # better than gp2
    volume_size = 20          # was 500GB (wasteful)
    encrypted   = true        # encrypt data at rest
  }

  tags = {
    Name = "orders-api"
  }
}

# ---------------------------------------------------------------------------
# Security Group (firewall rules)
# ---------------------------------------------------------------------------

resource "aws_security_group" "api" {
  name = "orders-api-sg"

  # Only allow HTTP from anywhere (for the web API)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow SSH only from internal network

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------------------------------------------------------------------------
# RDS Database (PostgreSQL)
# ---------------------------------------------------------------------------

# Generate a random strong password
# (instead of hardcoding "MyDbPassword123")
resource "random_password" "db_password" {
  length  = 32
  special = true
}

resource "aws_db_instance" "orders_db" {
  identifier        = "orders-db"
  engine            = "postgres"
  engine_version    = "16"
  instance_class    = "db.t3.micro"  # was db.m5.2xlarge (way too expensive)
  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "orders_db"
  username = "orders_admin"
  password = random_password.db_password.result

  publicly_accessible     = false   # don't expose DB to internet
  skip_final_snapshot     = true
  backup_retention_period = 7       # keep backups for 7 days

  tags = {
    Name = "orders-db"
  }
}