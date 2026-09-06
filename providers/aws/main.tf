locals {
  common_tags = merge(
    {
      Name      = var.cluster_name
      ManagedBy = "clusterdrill-lab"
      Purpose   = "disposable-clusterdrill-lab"
    },
    var.tags,
  )
}

# Canonical's own AWS account ID for official Ubuntu AMIs - a stable,
# publicly documented fact (https://ubuntu.com/server/docs/cloud-images/amazon-ec2),
# not this project's account.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "this" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = local.common_tags
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = local.common_tags
}

# A public IP per node is the point here, not an oversight: this is a
# single-operator disposable lab meant to be reached by direct SSH/kubectl
# (see the security group's SSH/API ingress rules, scoped to the
# operator's own CIDR) - a NAT gateway plus bastion would add real
# recurring cost and complexity for a lab meant to be torn down after a
# study session, with no security benefit over the CIDR restriction
# already in place.
#trivy:ignore:AWS-0164
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.42.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = local.common_tags
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = local.common_tags
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_key_pair" "this" {
  key_name   = var.cluster_name
  public_key = var.ssh_public_key

  tags = local.common_tags
}

resource "aws_security_group" "this" {
  name        = var.cluster_name
  description = "clusterdrill-lab: SSH and Kubernetes API from the operator CIDR, full traffic between nodes in this lab for pod networking/kubelet/etcd."
  vpc_id      = aws_vpc.this.id

  tags = local.common_tags
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.this.id
  description       = "SSH from the operator"
  cidr_ipv4         = var.allowed_ssh_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "kube_api" {
  security_group_id = aws_security_group.this.id
  description       = "Kubernetes API server from the operator, so kubectl can reach it directly"
  cidr_ipv4         = var.allowed_ssh_cidr
  from_port         = 6443
  to_port           = 6443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "nodeport_range" {
  security_group_id = aws_security_group.this.id
  description       = "NodePort services, from the operator, for questions that expose one"
  cidr_ipv4         = var.allowed_ssh_cidr
  from_port         = 30000
  to_port           = 32767
  ip_protocol       = "tcp"
}

# Every port between the lab's own nodes: pod-to-pod (Cilium VXLAN/Geneve),
# kubelet (10250), etcd (2379-2380), and anything else kubeadm/Cilium need -
# scoping this port-by-port would be brittle against future Cilium/kubeadm
# version changes, and it's already restricted to this lab's own nodes, not
# the internet.
resource "aws_vpc_security_group_ingress_rule" "intra_cluster" {
  security_group_id            = aws_security_group.this.id
  description                  = "All traffic between nodes in this lab"
  referenced_security_group_id = aws_security_group.this.id
  ip_protocol                  = "-1"
}

# Unrestricted egress is required, not incidental: bootstrap pulls from
# apt mirrors, Kubernetes package repos, the Cilium Helm chart/images, and
# arbitrary container images a practice question happens to reference -
# none of these resolve to a fixed, enumerable IP range, and this lab has
# no outbound proxy to funnel them through. This rule only opens egress,
# never inbound access; see the ingress rules above for what can reach
# these nodes.
#trivy:ignore:AWS-0104
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description       = "Outbound - package installs, container image pulls, apt/kubeadm/Cilium downloads"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_instance" "control_plane" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.control_plane_instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.this.id]
  key_name                    = aws_key_pair.this.key_name
  associate_public_ip_address = true

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-control-plane"
    Role = "control-plane"
  })
}

resource "aws_instance" "worker" {
  count = var.worker_count

  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.worker_instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.this.id]
  key_name                    = aws_key_pair.this.key_name
  associate_public_ip_address = true

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-worker-${count.index}"
    Role = "worker"
  })
}
