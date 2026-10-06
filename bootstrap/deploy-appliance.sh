#!/usr/bin/env bash
# Installs the clusterdrill appliance onto an already-bootstrapped cluster via
# its published Helm chart. Run on the control-plane node only, by run.sh,
# only when CLUSTERDRILL_DEPLOY=1 (see run.sh's own "Deploying the
# clusterdrill appliance" stage) and only after control-plane.sh has finished
# and every worker.sh has completed - the Deployment this creates has no
# toleration for the control-plane's own NoSchedule taint, so it can only
# schedule once at least one worker node has actually joined
# (CLUSTERDRILL_LAB_SINGLE_NODE=1 is the one exception, see control-plane.sh).
set -euo pipefail

if [ $# -gt 0 ]; then
  echo "usage: $0" >&2
  exit 1
fi

# The published clusterdrill chart version this bootstrap installs - the
# authoritative pin is compatibility.json's app.version, and
# check_compatibility_contract.sh enforces that the two never silently drift
# apart. The chart itself already carries this release's real image
# repository/digest as its own values.yaml default - nothing here resolves
# or passes an image reference. See compatibility.json's app.chart_repository
# for where this version is actually published.
CLUSTERDRILL_VERSION="0.1.6"
CLUSTERDRILL_CHART="oci://registry-1.docker.io/w00dson/clusterdrill-chart"
CLUSTERDRILL_NAMESPACE="clusterdrill-system"
CLUSTERDRILL_SECRET="clusterdrill-web-auth"

echo "control-plane: deploying the clusterdrill appliance (chart v${CLUSTERDRILL_VERSION})"

if ! kubectl get namespace "$CLUSTERDRILL_NAMESPACE" >/dev/null 2>&1; then
  kubectl create namespace "$CLUSTERDRILL_NAMESPACE"
fi

# The chart never generates or accepts a password value itself - only ever a
# reference (auth.existingSecretName) to a Secret that must already exist.
# Idempotent: a re-run against a lab that already has this Secret (e.g.
# resuming after a later step failed) reuses it rather than rotating the
# password out from under an operator who already has it.
if kubectl -n "$CLUSTERDRILL_NAMESPACE" get secret "$CLUSTERDRILL_SECRET" >/dev/null 2>&1; then
  echo "control-plane: reusing the existing ${CLUSTERDRILL_SECRET} secret"
  PASSWORD_PRINTED=0
else
  PASSWORD="$(openssl rand -base64 24 | tr -d '=+/')"
  kubectl -n "$CLUSTERDRILL_NAMESPACE" create secret generic "$CLUSTERDRILL_SECRET" \
    --from-literal=password="$PASSWORD"
  PASSWORD_PRINTED=1
fi

# No --set image.* flags - the published chart already has this version's
# real image repository/digest baked in as its own default (see
# compatibility.json's $comment and the chart's own README "Install"
# section). --wait is deliberately not used here: this repo's other
# bootstrap scripts wait on the rollout explicitly afterward instead, so a
# timeout produces the same "waiting for the appliance" message either way,
# not a different helm-specific one.
helm upgrade --install clusterdrill "$CLUSTERDRILL_CHART" \
  --version "$CLUSTERDRILL_VERSION" \
  --namespace "$CLUSTERDRILL_NAMESPACE" \
  --set auth.existingSecretName="$CLUSTERDRILL_SECRET"

echo "control-plane: waiting for the appliance to become ready"
kubectl -n "$CLUSTERDRILL_NAMESPACE" rollout status deployment/clusterdrill-web --timeout=5m

echo "control-plane: done"
if [ "$PASSWORD_PRINTED" -eq 1 ]; then
  echo "Login password: ${PASSWORD}"
else
  echo "Login password: unchanged - already set in the ${CLUSTERDRILL_SECRET} secret from a previous run"
fi
echo "The appliance is reachable via a NodePort (the chart's own default) - see your provider module's own README for how to reach it from your machine."
