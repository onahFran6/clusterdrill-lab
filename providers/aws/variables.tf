variable "aws_region" {
  description = "AWS region to provision the lab in."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name prefix applied to every resource this module creates (VPC, security group, instances, tags). Must be unique within your account/region if you run more than one lab at a time."
  type        = string
  default     = "clusterdrill-lab"
}

variable "worker_count" {
  description = "Number of worker nodes, in addition to the one control-plane node. 1 is the minimum useful lab; the practice bank's multi-node questions assume at least 1 worker."
  type        = number
  default     = 1

  validation {
    condition     = var.worker_count >= 1
    error_message = "worker_count must be at least 1 - a control-plane-only cluster can't run the practice bank's multi-node questions."
  }
}

variable "control_plane_instance_type" {
  description = "EC2 instance type for the control-plane node. kubeadm's own minimum is 2 vCPUs / 2 GiB RAM; t3.medium (2 vCPU / 4 GiB) is this module's tested default."
  type        = string
  default     = "t3.medium"
}

variable "control_plane_architecture" {
  description = "CPU architecture of control_plane_instance_type - selects which Ubuntu 22.04 AMI to launch it with. Must match the instance type's actual architecture (e.g. \"arm64\" for Graviton families like t4g/m7g/c7g, \"amd64\" for everything else) - Terraform has no way to derive this from the instance type string itself, since AWS's own family-naming convention isn't a machine-checkable contract."
  type        = string
  default     = "amd64"

  validation {
    condition     = contains(["amd64", "arm64"], var.control_plane_architecture)
    error_message = "control_plane_architecture must be \"amd64\" or \"arm64\"."
  }
}

variable "worker_instance_type" {
  description = "EC2 instance type for each worker node."
  type        = string
  default     = "t3.medium"
}

variable "worker_architecture" {
  description = "CPU architecture of worker_instance_type - selects which Ubuntu 22.04 AMI to launch every worker with. Every worker shares the same instance_type/architecture; a mixed-architecture worker fleet isn't supported by this module. See control_plane_architecture for the naming caveat - control-plane and workers may use different architectures from each other."
  type        = string
  default     = "amd64"

  validation {
    condition     = contains(["amd64", "arm64"], var.worker_architecture)
    error_message = "worker_architecture must be \"amd64\" or \"arm64\"."
  }
}

variable "ssh_public_key" {
  description = "Your own SSH public key (e.g. the contents of ~/.ssh/id_ed25519.pub), used to create the AWS key pair this module provisions nodes with. This module never generates or stores a private key - keep yours on your own machine."
  type        = string

  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-)", var.ssh_public_key))
    error_message = "ssh_public_key must be a public key (starts with ssh-ed25519, ssh-rsa, or ecdsa-sha2-...), not a private key or a file path."
  }
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to reach the nodes over SSH (port 22), e.g. \"203.0.113.4/32\" for just your own IP. No default on purpose - you must choose this deliberately rather than inherit an open one."
  type        = string

  validation {
    condition     = var.allowed_ssh_cidr != "0.0.0.0/0"
    error_message = "allowed_ssh_cidr must not be 0.0.0.0/0 - this lab is meant to be reachable by its operator only. Use your own IP's /32, or a VPN/office CIDR you control."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the lab's VPC. Change this if your own network (home, office, VPN) already uses part of the default range - 10.x is the most commonly used private range - or if you want to run more than one lab at once with non-overlapping networks."
  type        = string
  default     = "10.42.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block, e.g. \"10.42.0.0/16\"."
  }
}

variable "public_subnet_cidr" {
  description = "CIDR block for the lab's single public subnet. Must be a sub-range of vpc_cidr."
  type        = string
  default     = "10.42.1.0/24"

  validation {
    condition     = can(cidrhost(var.public_subnet_cidr, 0))
    error_message = "public_subnet_cidr must be a valid IPv4 CIDR block, e.g. \"10.42.1.0/24\"."
  }
}

variable "availability_zone" {
  description = "Availability zone (e.g. \"us-east-1a\") to provision the subnet and every node in. Defaults to null, which keeps today's behavior - the first AZ aws_region's own availability_zones data source happens to return. Set this explicitly if you need a specific AZ (e.g. capacity or pricing for a specific instance type)."
  type        = string
  default     = null
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size, in GiB, for every node."
  type        = number
  default     = 30
}

variable "root_volume_type" {
  description = "Root EBS volume type for every node."
  type        = string
  default     = "gp3"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2", "sc1", "st1", "standard"], var.root_volume_type)
    error_message = "root_volume_type must be one of: gp2, gp3, io1, io2, sc1, st1, standard."
  }
}

variable "tags" {
  description = "Additional tags applied to every resource this module creates, merged with the module's own name/purpose tags."
  type        = map(string)
  default     = {}
}
