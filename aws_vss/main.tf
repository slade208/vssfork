terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  vss_user_data = file("${path.module}/../deploy/aws/portable_demo/user_data.sh")
}

data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "vss" {
  name        = "vss-g4dn-sg"
  description = "VSS access"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "VSS backend"
    from_port   = 8100
    to_port     = 8100
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "VSS frontend"
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_key_pair" "vss" {
  key_name   = var.key_name
  public_key = file(var.public_key_path)
}

resource "aws_instance" "vss" {
  ami                         = var.ami_id
  instance_type               = "g4dn.2xlarge"
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.vss.id]
  key_name                    = aws_key_pair.vss.key_name
  associate_public_ip_address = true

  root_block_device {
    volume_size = 250
    volume_type = "gp3"
  }

  metadata_options {
    http_tokens = "required"
  }

  user_data = local.vss_user_data

  tags = {
    Name = "vss-g4dn-xlarge"
  }
}

output "public_ip" {
  value = aws_instance.vss.public_ip
}

output "ssh_cmd" {
  value = "ssh -i ${var.private_key_path} ubuntu@${aws_instance.vss.public_ip}"
}
