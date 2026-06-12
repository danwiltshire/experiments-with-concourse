packer {
  required_plugins {
    amazon = {
      version = ">= 1.3.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "concourse_version" {
  type        = string
  description = "Concourse release version to install, e.g. 7.11.2"
}

variable "aws_region" {
  type    = string
  default = "eu-west-2"
}

variable "instance_type" {
  type    = string
  # Workers need sufficient disk I/O; use a storage-optimised or compute type in production.
  default = "t3.medium"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID to launch the Packer build instance in."
}

variable "subnet_id" {
  type        = string
  description = "Public subnet ID to launch the Packer build instance in (requires internet access for SSH)."
}

locals {
  timestamp = formatdate("YYYY-MM-DD-hh-mm", timestamp())
}

source "amazon-ebs" "worker" {
  region        = var.aws_region
  instance_type = var.instance_type
  ami_name      = "concourse-worker-${var.concourse_version}-${local.timestamp}"
  ami_description = "Concourse worker node - concourse v${var.concourse_version}"

  source_ami_filter {
    filters = {
      name                = "al2023-ami-*-kernel-*-x86_64"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["137112412989"] # Amazon
  }

  vpc_id                      = var.vpc_id
  subnet_id                   = var.subnet_id
  associate_public_ip_address = true
  ssh_username                = "ec2-user"

  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name             = "concourse-worker"
    ConcourseVersion = var.concourse_version
    ConcourseRole    = "worker"
    BuiltAt          = local.timestamp
  }
}

build {
  sources = ["source.amazon-ebs.worker"]

  provisioner "file" {
    source      = "files/concourse-worker.service"
    destination = "/tmp/concourse-worker.service"
  }

  provisioner "file" {
    source      = "files/install.sh"
    destination = "/tmp/install.sh"
  }

  provisioner "shell" {
    environment_vars = [
      "CONCOURSE_VERSION=${var.concourse_version}",
      "CONCOURSE_ROLE=worker",
    ]
    inline = [
      "chmod +x /tmp/install.sh",
      "sudo -E /tmp/install.sh",
    ]
  }
}
