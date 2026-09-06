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

variable "worker_instance_type" {
  description = "EC2 instance type for each worker node."
  type        = string
  default     = "t3.medium"
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

variable "root_volume_size_gb" {
  description = "Root EBS volume size, in GiB, for every node."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Additional tags applied to every resource this module creates, merged with the module's own name/purpose tags."
  type        = map(string)
  default     = {}
}
