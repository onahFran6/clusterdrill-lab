# The common output contract every providers/* module must produce, so
# bootstrap/ can consume any of them identically without knowing which
# cloud ran. See providers/README.md.

output "control_plane_ip" {
  description = "Public IP of the control-plane node."
  value       = aws_instance.control_plane.public_ip
}

output "worker_ips" {
  description = "Public IPs of the worker nodes, in the same order as worker_count."
  value       = aws_instance.worker[*].public_ip
}

output "ssh_user" {
  description = "SSH username for every node (fixed by the AMI - Canonical's Ubuntu cloud images use 'ubuntu')."
  value       = "ubuntu"
}

output "ssh_key_name" {
  description = "The AWS key pair name every node was launched with - matches the identity of the private key that pairs with var.ssh_public_key on your own machine. This module never has, generates, or stores your private key."
  value       = aws_key_pair.this.key_name
}
