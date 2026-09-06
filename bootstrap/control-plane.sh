#!/usr/bin/env bash
# Runs only on the control-plane node, after node-common.sh. Written fresh
# against the public kubeadm docs and Cilium's own install docs
# (https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/) -
# no text or structure copied from any private or course-provided script.
set -euo pipefail

if [ $# -lt 1 ] || [ $# -gt 3 ]; then
  echo "usage: $0 <control-plane-public-ip> [github-token-file] [app-repo-override]" >&2
  exit 1
fi
CONTROL_PLANE_IP="$1"
GITHUB_TOKEN_FILE="${2:-}"

POD_CIDR="10.244.0.0/16"
CILIUM_CLI_VERSION="v0.16.16"
CILIUM_VERSION="1.16.5"

# The published clusterdrill application version this bootstrap installs,
# and the GitHub repository its release lives in. CLUSTERDRILL_APP_REPO
# defaults to the real, eventual standalone application repository - not
# whatever private staging repository this lab candidate happens to be
# developed inside today (see ../README.md's "Not for production use" and
# the app repository's own README "Release policy" section for why a
# fixed default here would otherwise go stale the moment either repository
# is actually extracted). $3 overrides it - a plain argument, not an
# environment variable, since it isn't sensitive and a `sudo` invocation
# of this script (as CI uses) does not reliably pass environment variables
# through by default.
CLUSTERDRILL_BOOTSTRAP_VERSION="0.1.0"
CLUSTERDRILL_APP_REPO="${3:-onahFran6/clusterdrill}"

echo "control-plane: kubeadm init"
# CONTROL_PLANE_IP is passed in by run.sh (from the provider module's own
# output), not self-detected via a cloud instance-metadata call - the
# metadata API's shape differs per cloud (AWS/GCP/Azure each use a
# different path scheme at 169.254.169.254), so calling it here would
# make this script cloud-specific. See ../providers/README.md.
sudo kubeadm init --pod-network-cidr="$POD_CIDR" --apiserver-cert-extra-sans="$CONTROL_PLANE_IP"

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

echo "control-plane: installing Cilium (v${CILIUM_VERSION})"
cilium install --version "$CILIUM_VERSION"
cilium status --wait

echo "control-plane: generating the worker join command"
sudo kubeadm token create --print-join-command | sudo tee /tmp/kubeadm-join-command.sh >/dev/null
sudo chmod 0644 /tmp/kubeadm-join-command.sh

echo "control-plane: installing the clusterdrill package (v${CLUSTERDRILL_BOOTSTRAP_VERSION})"
# The clusterdrill package requires Python >= 3.11 (pyproject.toml's
# requires-python), but Ubuntu 22.04's own default system python3 is 3.10
# - installing it explicitly and pointing pipx at it, rather than
# whatever `python3` resolves to, keeps this working on the documented
# Ubuntu 22.04 target (see ../compatibility.json's os.release) without
# depending on the distro's own default ever changing.
sudo apt-get install -y -qq python3-pip python3.11 python3.11-venv pipx
pipx ensurepath
export PATH="$HOME/.local/bin:$PATH"

# No clusterdrill package is published to PyPI (see the app repository's own
# README "Release policy" section) - the published GitHub Release's wheel
# asset is the only real install source today. The plain release-download
# URL is what this becomes with zero code change once the app repository
# itself is public; while it's still private, that URL 404s and this falls
# back to the GitHub API, authenticated with the token at GITHUB_TOKEN_FILE
# if one was supplied. Reading the token from a file (the same convention
# run.sh already uses for the SSH private key - a path, never a value)
# keeps it out of every process's command-line arguments and environment
# on both ends of the SSH connection, not just this remote one.
CLUSTERDRILL_WHEEL="clusterdrill-${CLUSTERDRILL_BOOTSTRAP_VERSION}-py3-none-any.whl"
WHEEL_PATH="/tmp/${CLUSTERDRILL_WHEEL}"
PUBLIC_URL="https://github.com/${CLUSTERDRILL_APP_REPO}/releases/download/v${CLUSTERDRILL_BOOTSTRAP_VERSION}/${CLUSTERDRILL_WHEEL}"

if curl -fsSL --output "$WHEEL_PATH" "$PUBLIC_URL" 2>/dev/null; then
  echo "control-plane: fetched ${CLUSTERDRILL_WHEEL} via the public release URL"
elif [ -n "$GITHUB_TOKEN_FILE" ] && [ -f "$GITHUB_TOKEN_FILE" ]; then
  echo "control-plane: public release fetch failed (the app repository is still private) - trying the GitHub API with the supplied token"
  # Cleaned up on every exit path (including the early-return failure
  # below), not just the success path.
  trap 'rm -f "$GITHUB_TOKEN_FILE"' EXIT
  GITHUB_TOKEN="$(cat "$GITHUB_TOKEN_FILE")"
  ASSET_ID="$(curl -fsSL -H "Authorization: token ${GITHUB_TOKEN}" \
    "https://api.github.com/repos/${CLUSTERDRILL_APP_REPO}/releases/tags/v${CLUSTERDRILL_BOOTSTRAP_VERSION}" \
    | python3 -c "import json,sys; a=[x for x in json.load(sys.stdin)['assets'] if x['name']=='${CLUSTERDRILL_WHEEL}']; print(a[0]['id'] if a else '')")"
  if [ -z "$ASSET_ID" ]; then
    echo "control-plane: could not find release asset ${CLUSTERDRILL_WHEEL} on v${CLUSTERDRILL_BOOTSTRAP_VERSION} - check the token can read ${CLUSTERDRILL_APP_REPO}" >&2
    exit 1
  fi
  curl -fsSL -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/octet-stream" \
    "https://api.github.com/repos/${CLUSTERDRILL_APP_REPO}/releases/assets/${ASSET_ID}" \
    -o "$WHEEL_PATH"
  unset GITHUB_TOKEN
else
  echo "control-plane: could not fetch ${CLUSTERDRILL_WHEEL} - the app repository is still private and no readable token file was supplied. Pass a GitHub token file as run.sh's third argument, or wait until that repository is public." >&2
  exit 1
fi

pipx install --python python3.11 "$WHEEL_PATH"

echo "control-plane: deploying the appliance"
# pipx installs into its own isolated venv, not system python3 - ask pipx
# itself where that venv lives (PIPX_LOCAL_VENVS) rather than hardcode a
# path, since that has changed across pipx versions. Within it, find
# whichever python* interpreter actually exists rather than assume a
# fixed name - not guaranteed given the explicit --python above.
PIPX_LOCAL_VENVS="$(pipx environment | sed -n 's/^PIPX_LOCAL_VENVS=//p')"
if [ -z "$PIPX_LOCAL_VENVS" ]; then
  echo "control-plane: could not determine PIPX_LOCAL_VENVS from 'pipx environment'" >&2
  pipx environment >&2 || true
  exit 1
fi
PIPX_VENV_BIN="${PIPX_LOCAL_VENVS}/clusterdrill/bin"
# `|| true`: compgen exits non-zero when nothing matches, which would
# otherwise abort the script right here under `set -e`, before the
# friendly error message below ever runs.
PIPX_PY="$(compgen -G "${PIPX_VENV_BIN}/python*" | sort | head -1 || true)"
if [ -z "$PIPX_PY" ]; then
  echo "control-plane: no python* interpreter found in ${PIPX_VENV_BIN}" >&2
  ls -la "$PIPX_VENV_BIN" >&2 || echo "control-plane: ${PIPX_VENV_BIN} does not exist" >&2
  exit 1
fi
MANIFEST_PATH="$("$PIPX_PY" -c 'import clusterdrill.cli as m; print(m.MANIFEST)')"
# Same resolution local_install() uses without --image: the release digest
# paired with the installed package version, or the clusterdrill:dev
# fallback - which won't exist on this remote node (nothing here builds an
# image from source). Until a release matching current source is
# published, this deploys the same known-stale image README.md's "Release
# policy" section warns about; this is a real, honest limitation of this
# script today, not a bug in it - see ../README.md's "Known limitations".
IMAGE="$("$PIPX_PY" -c 'from clusterdrill.release import resolve_default_image; print(resolve_default_image())')"
VERSION="$("$PIPX_PY" -c 'from clusterdrill.release import installed_version; print(installed_version() or "dev")')"
PASSWORD="$(openssl rand -base64 24 | tr -d '=+/')"
sed \
  -e "s#\${CLUSTERDRILL_IMAGE}#${IMAGE}#g" \
  -e "s#\${CLUSTERDRILL_PASSWORD}#${PASSWORD}#g" \
  -e "s#\${CLUSTERDRILL_VERSION}#${VERSION}#g" \
  "$MANIFEST_PATH" | kubectl apply -f -

echo "control-plane: waiting for the appliance to become ready"
kubectl -n clusterdrill-system rollout status deployment/clusterdrill-web --timeout=5m

echo "control-plane: done"
echo "Login password: ${PASSWORD}"
echo "The appliance is reachable via a NodePort - see your provider module's own README for how to reach it from your machine."
