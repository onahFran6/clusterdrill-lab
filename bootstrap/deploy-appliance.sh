#!/usr/bin/env bash
# Installs and deploys the clusterdrill appliance onto an already-bootstrapped
# cluster. Run on the control-plane node only, by run.sh, only after
# control-plane.sh has finished and every worker.sh has completed - the
# Deployment this creates has no toleration for the control-plane's own
# NoSchedule taint, so it can only schedule once at least one worker node
# has actually joined (CLUSTERDRILL_LAB_SINGLE_NODE=1 is the one exception,
# see control-plane.sh).
set -euo pipefail

if [ $# -gt 2 ]; then
  echo "usage: $0 [github-token-file] [app-repo-override]" >&2
  exit 1
fi
GITHUB_TOKEN_FILE="${1:-}"

# The published clusterdrill application version this bootstrap installs,
# and the GitHub repository its release lives in. CLUSTERDRILL_APP_REPO
# defaults to the real, eventual standalone application repository - not
# whatever private staging repository this lab candidate happens to be
# developed inside today (see ../README.md's "Not for production use" and
# the app repository's own README "Release policy" section for why a
# fixed default here would otherwise go stale the moment either repository
# is actually extracted). $2 overrides it - a plain argument, not an
# environment variable, since it isn't sensitive and a `sudo` invocation
# of this script (as CI uses) does not reliably pass environment variables
# through by default.
CLUSTERDRILL_BOOTSTRAP_VERSION="0.1.0"
CLUSTERDRILL_APP_REPO="${2:-onahFran6/clusterdrill}"

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
# Ubuntu 22.04's apt-shipped pipx is 1.0.0, which predates the `pipx
# environment` subcommand (added in 1.1.0) this script relies on below to
# locate pipx's own venv directory without hardcoding a path. Upgrade it
# via pip - decoupled from the python3.11 pinned above, pipx itself just
# needs to be new enough, not tied to any particular managed venv's
# interpreter.
python3 -m pip install --user --quiet --upgrade pipx

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
