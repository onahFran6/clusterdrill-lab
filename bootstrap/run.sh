#!/usr/bin/env bash
# Orchestrates node-common.sh, control-plane.sh, and worker.sh over SSH
# against whatever providers/<cloud> module produced - reads only the
# common output contract (control_plane_ip, worker_ips, ssh_user,
# ssh_key_name), never anything cloud-specific. See ../providers/README.md.
#
# Usage:
#   terraform -chdir=../providers/aws output -json > outputs.json
#   ./run.sh outputs.json ~/.ssh/id_ed25519
#   ./run.sh outputs.json ~/.ssh/id_ed25519 ~/.github-token   # while the
#     clusterdrill app repository is still private - see control-plane.sh
#   ./run.sh outputs.json ~/.ssh/id_ed25519 ~/.github-token owner/staging-repo
#     # also override which repository the release comes from, e.g. testing
#     # against a staging repository before the real app repository exists
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ $# -lt 2 ] || [ $# -gt 4 ]; then
  echo "usage: $0 <terraform-outputs.json> <ssh-private-key-path> [github-token-file] [app-repo-override]" >&2
  exit 1
fi
OUTPUTS_FILE="$1"
SSH_KEY="$2"
GITHUB_TOKEN_FILE="${3:-}"
APP_REPO_OVERRIDE="${4:-}"
if [ -n "$GITHUB_TOKEN_FILE" ] && [ ! -f "$GITHUB_TOKEN_FILE" ]; then
  echo "run.sh: github-token-file not found at $GITHUB_TOKEN_FILE" >&2
  exit 1
fi

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

wait_for_ssh() {
  local host="$1"
  echo "run.sh: waiting for SSH on $host"
  for _ in $(seq 1 30); do
    if ssh "${SSH_OPTS[@]}" "${SSH_USER}@${host}" true 2>/dev/null; then
      return 0
    fi
    sleep 10
  done
  echo "run.sh: timed out waiting for SSH on $host" >&2
  return 1
}

run_remote_script() {
  local host="$1"
  local script="$2"
  shift 2
  local remote_name quoted_args
  remote_name="$(basename "$script")"
  scp "${SSH_OPTS[@]}" -q "$script" "${SSH_USER}@${host}:/tmp/${remote_name}"
  # Quote each remaining arg with %q so an empty one (e.g. no token file,
  # but an app-repo-override after it) round-trips as its own '' word
  # instead of vanishing - plain "$*"/"$@" interpolated into one bigger
  # string here would let the remote shell's word-splitting silently
  # collapse an empty middle argument into the one after it.
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

for host in "$CONTROL_PLANE_IP" "${WORKER_IPS[@]}"; do
  wait_for_ssh "$host"
  # node-common.sh and (later, control-plane-only) deploy-appliance.sh
  # source lib/os-family.sh and lib/{debian,rhel}.sh by a SCRIPT_DIR-relative
  # path - run_remote_script only ever transfers the one script it's about
  # to invoke, flattened to /tmp/<name>, so lib/ has to be shipped here too,
  # to the exact sibling path (/tmp/lib) that flattening implies. Only once
  # per host: deploy-appliance.sh runs later in this same script but only on
  # $CONTROL_PLANE_IP, which already has /tmp/lib from this loop iteration.
  scp "${SSH_OPTS[@]}" -rq "${SCRIPT_DIR}/lib" "${SSH_USER}@${host}:/tmp/lib"
  run_remote_script "$host" "${SCRIPT_DIR}/node-common.sh"
done

echo "run.sh: bootstrapping the control plane"
run_remote_script "$CONTROL_PLANE_IP" "${SCRIPT_DIR}/control-plane.sh" "$CONTROL_PLANE_IP"

echo "run.sh: fetching the join command"
scp "${SSH_OPTS[@]}" -q "${SSH_USER}@${CONTROL_PLANE_IP}:/tmp/kubeadm-join-command.sh" /tmp/kubeadm-join-command.sh

for host in "${WORKER_IPS[@]}"; do
  echo "run.sh: joining worker $host"
  scp "${SSH_OPTS[@]}" -q /tmp/kubeadm-join-command.sh "${SSH_USER}@${host}:/tmp/kubeadm-join-command.sh"
  run_remote_script "$host" "${SCRIPT_DIR}/worker.sh"
done
rm -f /tmp/kubeadm-join-command.sh

# Deploying the appliance only after every worker has joined, not right
# after control-plane.sh: its Deployment has no toleration for the
# control-plane's own NoSchedule taint, so in a real multi-node lab it can
# only ever schedule once a worker actually exists to run on - deploying
# it any earlier just hangs until kubectl rollout status's own timeout.
echo "run.sh: deploying the clusterdrill appliance"
REMOTE_TOKEN_FILE=""
if [ -n "$GITHUB_TOKEN_FILE" ]; then
  REMOTE_TOKEN_FILE="/tmp/clusterdrill-github-token"
  scp "${SSH_OPTS[@]}" -q "$GITHUB_TOKEN_FILE" "${SSH_USER}@${CONTROL_PLANE_IP}:${REMOTE_TOKEN_FILE}"
  # REMOTE_TOKEN_FILE is a fixed literal this script sets above, not user
  # input - client-side expansion here is intentional, same as
  # run_remote_script's own remote_name below.
  # shellcheck disable=SC2029
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${CONTROL_PLANE_IP}" "chmod 600 ${REMOTE_TOKEN_FILE}"
fi
run_remote_script "$CONTROL_PLANE_IP" "${SCRIPT_DIR}/deploy-appliance.sh" "$REMOTE_TOKEN_FILE" "$APP_REPO_OVERRIDE"

# Same ordering reason as the appliance above - and same reason it needs its
# own explicit scp: run_remote_script only transfers the one script it's
# about to invoke, not files that script references.
echo "run.sh: deploying the Headlamp dashboard"
scp "${SSH_OPTS[@]}" -q "${SCRIPT_DIR}/../dashboard/headlamp-manifest.yaml" "${SSH_USER}@${CONTROL_PLANE_IP}:/tmp/headlamp-manifest.yaml"
run_remote_script "$CONTROL_PLANE_IP" "${SCRIPT_DIR}/deploy-headlamp.sh"

echo "run.sh: done. SSH to the control plane to use kubectl:"
echo "  ssh -i ${SSH_KEY} ${SSH_USER}@${CONTROL_PLANE_IP}"
