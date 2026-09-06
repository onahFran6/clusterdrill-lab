#!/usr/bin/env bash
# Runs only on a worker node, after node-common.sh. Expects
# /tmp/kubeadm-join-command.sh (produced by control-plane.sh and copied
# here by run.sh) to already be present.
set -euo pipefail

JOIN_COMMAND_FILE="/tmp/kubeadm-join-command.sh"

if [ ! -f "$JOIN_COMMAND_FILE" ]; then
  echo "worker: $JOIN_COMMAND_FILE not found - run control-plane.sh first and copy it here" >&2
  exit 1
fi

echo "worker: joining the cluster"
sudo bash "$JOIN_COMMAND_FILE"

echo "worker: done"
