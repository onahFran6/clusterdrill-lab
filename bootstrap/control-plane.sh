#!/usr/bin/env bash
# Runs only on the control-plane node, after node-common.sh. Written fresh
# against the public kubeadm docs and Cilium's own install docs
# (https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/) -
# no text or structure copied from any private or course-provided script.
#
# Only initializes the control plane and installs Cilium - it stops at
# generating the worker join command. Deploying the clusterdrill appliance
# itself is deploy-appliance.sh, run separately by run.sh only after every
# worker has joined: the appliance's Deployment has no toleration for the
# control-plane's own NoSchedule taint (the CLUSTERDRILL_LAB_SINGLE_NODE
# escape hatch below is the one exception), so in a real multi-node lab it
# can only ever schedule once a worker node actually exists to run on -
# calling it from here, before any worker has joined, would just hang
# until kubectl rollout status's own timeout and fail.
#
# Idempotent, like node-common.sh: safe to re-run if a partial bootstrap
# (e.g. a later step in run.sh, over the same SSH session) failed partway
# through. `kubeadm init` and `cilium install` both refuse to run again
# once they've already succeeded once on this node - re-running either
# unconditionally would fail with "port already in use" /
# "already installed" errors instead of picking up where run.sh left off.
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <control-plane-public-ip>" >&2
  exit 1
fi
CONTROL_PLANE_IP="$1"

POD_CIDR="10.244.0.0/16"
CILIUM_CLI_VERSION="v0.16.16"
CILIUM_VERSION="1.16.5"

# /etc/kubernetes/admin.conf only exists once `kubeadm init` has actually
# succeeded on this node - the same signal kubeadm itself relies on.
if [ -f /etc/kubernetes/admin.conf ]; then
  echo "control-plane: kubeadm already initialized this node (found /etc/kubernetes/admin.conf) - skipping kubeadm init"
else
  echo "control-plane: kubeadm init"
  # CONTROL_PLANE_IP is passed in by run.sh (from the provider module's own
  # output), not self-detected via a cloud instance-metadata call - the
  # metadata API's shape differs per cloud (AWS/GCP/Azure each use a
  # different path scheme at 169.254.169.254), so calling it here would
  # make this script cloud-specific. See ../providers/README.md.
  sudo kubeadm init --pod-network-cidr="$POD_CIDR" --apiserver-cert-extra-sans="$CONTROL_PLANE_IP"
fi

echo "control-plane: setting up kubeconfig for $(whoami)"
mkdir -p "$HOME/.kube"
sudo cp -f /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

# A real lab always provisions at least one worker (variables.tf's
# worker_count validation requires >= 1), so the control-plane's default
# NoSchedule taint is correct and left alone - regular workloads schedule
# onto the worker(s), exactly what they're for. CLUSTERDRILL_LAB_SINGLE_NODE=1
# is a CI-only escape hatch (see .github/workflows/lab-quality-gate.yml's
# app-lab-compatibility-e2e job) for testing this bootstrap flow on a
# single runner with no separate worker at all - never set it against a
# real lab.
if [ "${CLUSTERDRILL_LAB_SINGLE_NODE:-}" = "1" ]; then
  echo "control-plane: CLUSTERDRILL_LAB_SINGLE_NODE=1 - removing the control-plane's NoSchedule taint so the appliance can run on this one node"
  kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true
fi

echo "control-plane: installing the Cilium CLI"
# Same uname-m-to-arch mapping bootstrap/lib/practice-tools.sh's
# _practice_tools_goarch has for Helm/Kustomize - duplicated rather than
# shared since this script sources no lib/ file today; see that function's
# own comment.
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) CILIUM_ARCH="amd64" ;;
  aarch64) CILIUM_ARCH="arm64" ;;
  *) echo "control-plane: unsupported architecture $ARCH" >&2; exit 1 ;;
esac
curl -fsSL --output cilium-linux.tar.gz \
  "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CILIUM_ARCH}.tar.gz"
sudo tar -xzf cilium-linux.tar.gz -C /usr/local/bin cilium
rm -f cilium-linux.tar.gz

# `cilium install` errors out if Cilium is already installed on this
# cluster - checking `cilium status` first (a single check, not --wait)
# is the same "already done" signal used above for kubeadm init, just
# via the Cilium CLI's own health check instead of a file on disk.
if cilium status >/dev/null 2>&1; then
  echo "control-plane: Cilium is already installed and healthy - skipping cilium install"
else
  echo "control-plane: installing Cilium (v${CILIUM_VERSION})"
  cilium install --version "$CILIUM_VERSION"
fi
cilium status --wait

echo "control-plane: generating the worker join command"
sudo kubeadm token create --print-join-command | sudo tee /tmp/kubeadm-join-command.sh >/dev/null
sudo chmod 0644 /tmp/kubeadm-join-command.sh
