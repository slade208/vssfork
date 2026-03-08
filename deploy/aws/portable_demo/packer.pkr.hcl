packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = ">= 1.3.0"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "us-west-1"
}

variable "subnet_id" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "g4dn.xlarge"
}

variable "ssh_username" {
  type    = string
  default = "ubuntu"
}

variable "ami_name_prefix" {
  type    = string
  default = "vss-gpu-demo"
}

source "amazon-ebs" "ubuntu_vss_gpu" {
  region                      = var.aws_region
  instance_type               = var.instance_type
  ssh_username                = var.ssh_username
  subnet_id                   = var.subnet_id
  vpc_id                      = var.vpc_id
  associate_public_ip_address = true

  ami_name        = "${var.ami_name_prefix}-${formatdate("YYYYMMDD-hhmm", timestamp())}"
  ami_description = "Ubuntu 22.04 + NVIDIA driver + Docker + NVIDIA container toolkit for VSS demos"

  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["099720109477"]
    most_recent = true
  }

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 250
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "vss-gpu-base"
    Role = "demo"
  }
}

build {
  name    = "vss-gpu-ami"
  sources = ["source.amazon-ebs.ubuntu_vss_gpu"]

  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline = [
      "set -uxo pipefail",
      "export DEBIAN_FRONTEND=noninteractive",
      "sudo apt-get update -y",
      "sudo apt-get install -y curl ca-certificates gnupg lsb-release software-properties-common ubuntu-drivers-common git git-lfs docker.io jq",
      "sudo apt-get install -y docker-compose-plugin || sudo apt-get install -y docker-compose-v2",
      "sudo systemctl enable docker",
      "sudo systemctl start docker",
      "sudo usermod -aG docker ubuntu",
      "sudo git lfs install --system",
      "sudo ubuntu-drivers install --gpgpu",
    ]
  }

  provisioner "shell" {
    expect_disconnect = true
    inline            = ["sudo reboot"]
  }

  provisioner "shell" {
    pause_before = "45s"
    inline_shebang = "/bin/bash -e"
    inline = [
      "set -uxo pipefail",
      "export DEBIAN_FRONTEND=noninteractive",
      "curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg",
      "curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#' | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list",
      "sudo apt-get update -y",
      "sudo apt-get install -y nvidia-container-toolkit nvidia-utils-590-server",
      "sudo nvidia-ctk runtime configure --runtime=docker",
      "sudo systemctl restart docker",
      "nvidia-smi",
      "sudo docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi",
      "sudo apt-get clean",
    ]
  }
}
