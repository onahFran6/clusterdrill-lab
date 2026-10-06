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

# SCRIPT_DIR-relative, not a fixed repo-relative path - when run.sh drives
# this over SSH, this script lands flattened at /tmp/node-common.sh, and
# run.sh's own per-host loop copies bootstrap/lib/ alongside it to /tmp/lib
# specifically so this resolves the same way there as it does when this
# script runs from a full repo checkout (e.g. this file's own CI job). See
# run.sh's "scp -r ... /tmp/lib" comment for the other half of this coupling.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/lib/os-family.sh
source "${SCRIPT_DIR}/lib/os-family.sh"
OS_FAMILY="$(detect_os_family)"
echo "node-common: detected OS family: ${OS_FAMILY}"
# shellcheck disable=SC1090 # dynamic path, resolved to one of this
# directory's own lib/{debian,rhel}.sh at runtime - see os-family.sh.
source "${SCRIPT_DIR}/lib/${OS_FAMILY}.sh"
# Not family-dispatched like the source above - practice-tools.sh installs
# the same way regardless of OS family, see its own header comment.
# shellcheck source=bootstrap/lib/practice-tools.sh
source "${SCRIPT_DIR}/lib/practice-tools.sh"

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

os_install_containerd

os_install_kube_packages "$KUBERNETES_MINOR"

install_helm
install_kustomize

echo "node-common: done"
