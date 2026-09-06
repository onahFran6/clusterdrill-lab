#!/usr/bin/env bash
# Verifies ../compatibility.json's pinned versions match the literal pins
# in node-common.sh and deploy-appliance.sh - the three are hand-maintained
# together (see compatibility.json's own "$comment") and must never
# silently drift apart. Run from clusterdrill-lab/bootstrap/ or pass its
# own directory as $1.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(dirname "$SCRIPT_DIR")"

CONTRACT_VERSION="$(python3 -c "import json; print(json.load(open('${LAB_DIR}/compatibility.json'))['app']['version'])")"
CONTRACT_K8S_MINOR="$(python3 -c "import json; print(json.load(open('${LAB_DIR}/compatibility.json'))['kubernetes']['bootstrap_pinned_minor'])")"

FAIL=0
if ! grep -q "CLUSTERDRILL_BOOTSTRAP_VERSION=\"${CONTRACT_VERSION}\"" "${SCRIPT_DIR}/deploy-appliance.sh"; then
  echo "compatibility.json's app.version (${CONTRACT_VERSION}) does not match bootstrap/deploy-appliance.sh's CLUSTERDRILL_BOOTSTRAP_VERSION" >&2
  FAIL=1
fi
if ! grep -q "KUBERNETES_MINOR=\"${CONTRACT_K8S_MINOR}\"" "${SCRIPT_DIR}/node-common.sh"; then
  echo "compatibility.json's kubernetes.bootstrap_pinned_minor (${CONTRACT_K8S_MINOR}) does not match bootstrap/node-common.sh's KUBERNETES_MINOR" >&2
  FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then
  echo "check_compatibility_contract: compatibility.json matches the bootstrap scripts' pinned versions"
fi
exit "$FAIL"
