#!/usr/bin/env bash
# Runs only on a worker node, after node-common.sh. Expects
# /tmp/kubeadm-join-command.sh (produced by control-plane.sh and copied
# here by run.sh) to already be present.
#
# Idempotent, like node-common.sh and control-plane.sh: safe to re-run if
# a partial bootstrap failed on a later node/step. `kubeadm join` refuses
# to run again once this node has already joined - re-running it
# unconditionally would fail with "port already in use" errors instead
# of picking up where run.sh left off.
set -euo pipefail

JOIN_COMMAND_FILE="/tmp/kubeadm-join-command.sh"

# /etc/kubernetes/kubelet.conf only exists once `kubeadm join` has
# actually succeeded on this node - the same signal used on the
# control-plane side for `kubeadm init`.
if [ -f /etc/kubernetes/kubelet.conf ]; then
  echo "worker: already joined this cluster (found /etc/kubernetes/kubelet.conf) - skipping kubeadm join"
else
  if [ ! -f "$JOIN_COMMAND_FILE" ]; then
    echo "worker: $JOIN_COMMAND_FILE not found - run control-plane.sh first and copy it here" >&2
    exit 1
  fi
  echo "worker: joining the cluster"
  sudo bash "$JOIN_COMMAND_FILE"
fi

echo "worker: done"
