#!/usr/bin/env bash
# Runs on every node (control-plane and worker alike) before kubeadm does
# anything node-role-specific. Written fresh against the public kubeadm
# install docs (https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)
# and the containerd docs (https://kubernetes.io/docs/setup/production-environment/container-runtimes/)
# - no text or structure copied from any private or course-provided script.
#
# Idempotent: safe to re-run if a partial bootstrap failed partway through.
set -euo pipefail

KUBERNETES_MINOR="1.33"

echo "node-common: disabling swap"
sudo swapoff -a
sudo sed -i '/\sswap\s/s/^/#/' /etc/fstab

echo "node-common: loading kernel modules kubeadm needs"
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf >/dev/null
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

echo "node-common: kernel network settings kubeadm needs"
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf >/dev/null
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system >/dev/null

echo "node-common: installing containerd"
sudo apt-get update -qq
sudo apt-get install -y -qq containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
# kubelet's own default cgroup driver is systemd; containerd's default
# config.toml ships with SystemdCgroup = false, which silently mismatches
# and produces a kubelet that starts but never reports Ready.
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd >/dev/null

echo "node-common: installing kubelet, kubeadm, kubectl (v${KUBERNETES_MINOR})"
sudo apt-get install -y -qq apt-transport-https ca-certificates curl gpg
sudo mkdir -p /etc/apt/keyrings
# --yes --batch: dearmor non-interactively even if the destination already
# exists (e.g. a pre-provisioned image that already ships this exact
# keyring) - without it, gpg prompts to overwrite via /dev/tty, which
# doesn't exist in a non-interactive SSH/CI invocation, contradicting this
# script's own "safe to re-run" claim above.
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_MINOR}/deb/Release.key" \
  | sudo gpg --yes --batch --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_MINOR}/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
sudo apt-get update -qq
sudo apt-get install -y -qq kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl >/dev/null

sudo systemctl enable kubelet >/dev/null

echo "node-common: done"
