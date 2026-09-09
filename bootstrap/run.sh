#!/usr/bin/env bash
# Orchestrates node-common.sh, control-plane.sh, and worker.sh over SSH
# against whatever providers/<cloud> module produced - reads only the
# common output contract (control_plane_ip, worker_ips, ssh_user,
# ssh_key_name), never anything cloud-specific. See ../providers/README.md.
#
# Usage:
#   terraform -chdir=../providers/aws output -json > outputs.json
#   ./run.sh outputs.json ~/.ssh/id_ed25519
#
#   # Also install the clusterdrill appliance into the lab cluster - unset,
#   # this produces a bare Kubernetes cluster with no clusterdrill footprint
#   # at all. See deploy-appliance.sh and compatibility.json's app.version
#   # for exactly what gets installed.
#   CLUSTERDRILL_DEPLOY=1 ./run.sh outputs.json ~/.ssh/id_ed25519
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ $# -ne 2 ]; then
  echo "usage: $0 <terraform-outputs.json> <ssh-private-key-path>" >&2
  exit 1
fi
OUTPUTS_FILE="$1"
SSH_KEY="$2"
CLUSTERDRILL_DEPLOY="${CLUSTERDRILL_DEPLOY:-}"

if ! command -v jq >/dev/null 2>&1; then
  echo "run.sh: jq is required (brew install jq / apt install jq)" >&2
  exit 1
fi
if [ ! -f "$OUTPUTS_FILE" ]; then
  echo "run.sh: $OUTPUTS_FILE not found - run 'terraform output -json > $OUTPUTS_FILE' first" >&2
  exit 1
fi
if [ ! -f "$SSH_KEY" ]; then
  echo "run.sh: SSH private key not found at $SSH_KEY" >&2
  exit 1
fi

CONTROL_PLANE_IP="$(jq -r '.control_plane_ip.value' "$OUTPUTS_FILE")"
mapfile -t WORKER_IPS < <(jq -r '.worker_ips.value[]' "$OUTPUTS_FILE")
SSH_USER="$(jq -r '.ssh_user.value' "$OUTPUTS_FILE")"

if [ -z "$CONTROL_PLANE_IP" ] || [ "$CONTROL_PLANE_IP" = "null" ]; then
  echo "run.sh: control_plane_ip missing from $OUTPUTS_FILE - did 'terraform apply' finish?" >&2
  exit 1
fi

SSH_OPTS=(-i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)

# Five stages the rest of this script always runs, in order, regardless of
# worker_count - see docs/BOOTSTRAP-DEEPDIVE.md's "Order of operations".
# Purely cosmetic bookkeeping (progress banners a human watching this run
# can actually scan), not control flow.
STAGE_TOTAL=5
STAGE_NUM=0
CURRENT_STAGE=""

stage() {
  STAGE_NUM=$((STAGE_NUM + 1))
  CURRENT_STAGE="$1"
  STAGE_STARTED=$SECONDS
  echo
  echo "==> [${STAGE_NUM}/${STAGE_TOTAL}] ${CURRENT_STAGE}"
}

stage_done() {
  echo "<== [${STAGE_NUM}/${STAGE_TOTAL}] ${CURRENT_STAGE} - done ($((SECONDS - STAGE_STARTED))s)"
}

# Fires only on an actual failure (set -e tripping on a non-zero exit
# somewhere below) - names which of the five stages was in flight, since
# the raw error above it (an SSH failure, a remote script's own error)
# doesn't otherwise say where in the run that happened.
trap '[ -n "$CURRENT_STAGE" ] && echo "run.sh: failed during [${STAGE_NUM}/${STAGE_TOTAL}] ${CURRENT_STAGE} (see the error above)" >&2' ERR

wait_for_ssh() {
  local host="$1"
  local waited=0
  for _ in $(seq 1 30); do
    if ssh "${SSH_OPTS[@]}" "${SSH_USER}@${host}" true 2>/dev/null; then
      [ "$waited" -eq 1 ] && echo "run.sh: SSH is back up on $host"
      return 0
    fi
    # Only announce once an attempt has actually failed - the common case
    # (SSH already answers) would otherwise print "waiting" noise on every
    # single run_remote_script call for no reason.
    [ "$waited" -eq 0 ] && echo "run.sh: waiting for SSH on $host"
    waited=1
    sleep 10
  done
  echo "run.sh: timed out waiting for SSH on $host" >&2
  return 1
}

run_remote_script() {
  local host="$1"
  local script="$2"
  shift 2
  # Re-checks SSH even though the per-host loop below already waited for
  # it once - a later call here (control-plane.sh, deploy-appliance.sh,
  # deploy-headlamp.sh) can hit a transient SSH blip (observed in
  # practice: banner-exchange timeout mid-run, on a host that had
  # answered SSH fine moments earlier, no reboot or code change
  # involved). wait_for_ssh returns immediately once SSH already
  # answers, so this is a no-op in the common case and a bounded retry
  # in the uncommon one, instead of the whole run dying on a blip it
  # could have waited out.
  wait_for_ssh "$host"
  local remote_name quoted_args
  remote_name="$(basename "$script")"
  scp "${SSH_OPTS[@]}" -q "$script" "${SSH_USER}@${host}:/tmp/${remote_name}"
  # Quote each remaining arg with %q so it round-trips as its own word,
  # including an empty one, instead of vanishing - plain "$*"/"$@"
  # interpolated into one bigger string here would let the remote shell's
  # word-splitting silently collapse an empty middle argument into the one
  # after it.
  quoted_args=""
  for arg in "$@"; do
    quoted_args+=" $(printf '%q' "$arg")"
  done
  # remote_name and quoted_args are expanded locally on purpose - a fixed
  # command string sent to the remote shell, not something evaluated
  # remotely.
  # shellcheck disable=SC2029
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${host}" "bash /tmp/${remote_name}${quoted_args}"
}

echo "run.sh: control-plane is ${CONTROL_PLANE_IP}, ${#WORKER_IPS[@]} worker(s): ${WORKER_IPS[*]}"

stage "Preparing nodes (node-common.sh) on the control-plane + ${#WORKER_IPS[@]} worker(s)"
for host in "$CONTROL_PLANE_IP" "${WORKER_IPS[@]}"; do
  wait_for_ssh "$host"
  # node-common.sh sources lib/os-family.sh and lib/{debian,rhel}.sh by a
  # SCRIPT_DIR-relative path - run_remote_script only ever transfers the one
  # script it's about to invoke, flattened to /tmp/<name>, so lib/ has to be
  # shipped here too, to the exact sibling path (/tmp/lib) that flattening
  # implies. The explicit rm -rf first matters on a re-run against a host
  # that already has /tmp/lib from an earlier invocation: scp -r copies a
  # source directory INTO an already-existing destination directory rather
  # than overwriting it (producing a stale, nested /tmp/lib/lib/*.sh instead
  # of updating /tmp/lib/*.sh directly) - found by hitting it on a real
  # re-run, not in theory.
  # shellcheck disable=SC2029
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${host}" "rm -rf /tmp/lib"
  scp "${SSH_OPTS[@]}" -rq "${SCRIPT_DIR}/lib" "${SSH_USER}@${host}:/tmp/lib"
  run_remote_script "$host" "${SCRIPT_DIR}/node-common.sh"
done
stage_done

stage "Bootstrapping the control plane (kubeadm init, Cilium)"
run_remote_script "$CONTROL_PLANE_IP" "${SCRIPT_DIR}/control-plane.sh" "$CONTROL_PLANE_IP"

echo "run.sh: fetching the join command"
scp "${SSH_OPTS[@]}" -q "${SSH_USER}@${CONTROL_PLANE_IP}:/tmp/kubeadm-join-command.sh" /tmp/kubeadm-join-command.sh
stage_done

stage "Joining ${#WORKER_IPS[@]} worker(s) to the cluster"
for host in "${WORKER_IPS[@]}"; do
  echo "run.sh: joining worker $host"
  scp "${SSH_OPTS[@]}" -q /tmp/kubeadm-join-command.sh "${SSH_USER}@${host}:/tmp/kubeadm-join-command.sh"
  run_remote_script "$host" "${SCRIPT_DIR}/worker.sh"
done
rm -f /tmp/kubeadm-join-command.sh
stage_done

# Deploying the appliance only after every worker has joined, not right
# after control-plane.sh: its Deployment has no toleration for the
# control-plane's own NoSchedule taint, so in a real multi-node lab it can
# only ever schedule once a worker actually exists to run on - deploying
# it any earlier just hangs until kubectl rollout status's own timeout.
#
# Explicit opt-in, not a default side effect of bringing the lab up - unset,
# this stage is a no-op and the lab is left as a bare, working Kubernetes
# cluster with no clusterdrill footprint at all. Set CLUSTERDRILL_DEPLOY=1
# (see this script's own usage comment at the top) to have it installed via
# deploy-appliance.sh's helm install/upgrade against the published chart.
# Independent of Terraform/the rest of the cluster: bring just this piece
# down again later with
# `ssh ... helm uninstall clusterdrill --namespace clusterdrill-system`.
stage "Deploying the clusterdrill appliance"
if [ "$CLUSTERDRILL_DEPLOY" = "1" ]; then
  run_remote_script "$CONTROL_PLANE_IP" "${SCRIPT_DIR}/deploy-appliance.sh"
else
  echo "run.sh: CLUSTERDRILL_DEPLOY is not set to 1 - skipping (see this script's usage comment)"
fi
stage_done

# Same ordering reason as the appliance above - and same reason it needs its
# own explicit scp: run_remote_script only transfers the one script it's
# about to invoke, not files that script references.
stage "Deploying the Headlamp dashboard"
scp "${SSH_OPTS[@]}" -q "${SCRIPT_DIR}/../dashboard/headlamp-manifest.yaml" "${SSH_USER}@${CONTROL_PLANE_IP}:/tmp/headlamp-manifest.yaml"
run_remote_script "$CONTROL_PLANE_IP" "${SCRIPT_DIR}/deploy-headlamp.sh"

# Queried fresh rather than scraped from deploy-headlamp.sh's own stdout
# above - the NodePort is a stable fact the API server already knows, so
# asking it directly is simpler than parsing a remote script's output.
HEADLAMP_NODEPORT="$(ssh "${SSH_OPTS[@]}" "${SSH_USER}@${CONTROL_PLANE_IP}" \
  "kubectl -n headlamp-system get svc headlamp -o jsonpath='{.spec.ports[0].nodePort}'")"
stage_done

echo
echo "run.sh: done."
echo
echo "SSH to the control plane:"
echo "  ssh -i ${SSH_KEY} ${SSH_USER}@${CONTROL_PLANE_IP}"
echo
echo "Headlamp dashboard: http://${CONTROL_PLANE_IP}:${HEADLAMP_NODEPORT}"
echo "  Log in with a bearer token (short-lived by design - generate one on demand):"
echo "  ssh -i ${SSH_KEY} ${SSH_USER}@${CONTROL_PLANE_IP} kubectl create token headlamp -n headlamp-system --duration=8h"
