#!/usr/bin/env bash
# Installs the Headlamp dashboard (https://github.com/kubernetes-sigs/headlamp)
# onto an already-bootstrapped cluster. Run on the control-plane node only, by
# run.sh, only after control-plane.sh has finished and every worker.sh has
# completed - like deploy-appliance.sh, this Deployment has no toleration for
# the control-plane's own NoSchedule taint, so it can only schedule once at
# least one worker node has actually joined.
#
# Expects ../dashboard/headlamp-manifest.yaml to already be copied to
# /tmp/headlamp-manifest.yaml (run.sh does this the same way it copies
# /tmp/kubeadm-join-command.sh - run_remote_script only transfers the one
# script it's invoking, not files it references, so the manifest needs its
# own explicit scp).
set -euo pipefail

if [ $# -ne 0 ]; then
  echo "usage: $0" >&2
  exit 1
fi

MANIFEST="/tmp/headlamp-manifest.yaml"
if [ ! -f "$MANIFEST" ]; then
  echo "deploy-headlamp: $MANIFEST not found - run.sh must scp dashboard/headlamp-manifest.yaml there first" >&2
  exit 1
fi

echo "control-plane: deploying Headlamp"
kubectl apply -f "$MANIFEST"

echo "control-plane: waiting for Headlamp to become ready"
kubectl -n headlamp-system rollout status deployment/headlamp --timeout=5m

NODEPORT="$(kubectl -n headlamp-system get svc headlamp -o jsonpath='{.spec.ports[0].nodePort}')"
echo "control-plane: done"
echo "Headlamp is reachable via NodePort ${NODEPORT} - see your provider module's own README for how to reach it from your machine."
echo "Log in with a bearer token generated on demand - it is never printed by this script since"
echo "kubectl create token tokens are short-lived by design:"
echo "  kubectl create token headlamp -n headlamp-system --duration=8h"
