#!/usr/bin/env bash
# Verifies ../compatibility.json's pinned versions match the literal pins
# in node-common.sh, deploy-appliance.sh, dashboard/headlamp-manifest.yaml,
# and ../providers/aws/main.tf's Ubuntu AMI filters - all hand-maintained
# together (see compatibility.json's own "$comment") and must never
# silently drift apart. Run from clusterdrill-lab/bootstrap/ or pass its
# own directory as $1.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(dirname "$SCRIPT_DIR")"

CONTRACT_VERSION="$(python3 -c "import json; print(json.load(open('${LAB_DIR}/compatibility.json'))['app']['version'])")"
CONTRACT_K8S_MINOR="$(python3 -c "import json; print(json.load(open('${LAB_DIR}/compatibility.json'))['kubernetes']['bootstrap_pinned_minor'])")"
CONTRACT_DASHBOARD_IMAGE="$(python3 -c "import json; print(json.load(open('${LAB_DIR}/compatibility.json'))['dashboard']['image'])")"
CONTRACT_OS_RELEASE="$(python3 -c "import json; print(json.load(open('${LAB_DIR}/compatibility.json'))['os']['release'])")"

FAIL=0
if ! grep -q "CLUSTERDRILL_VERSION=\"${CONTRACT_VERSION}\"" "${SCRIPT_DIR}/deploy-appliance.sh"; then
  echo "compatibility.json's app.version (${CONTRACT_VERSION}) does not match bootstrap/deploy-appliance.sh's CLUSTERDRILL_VERSION" >&2
  FAIL=1
fi
if ! grep -q "KUBERNETES_MINOR=\"${CONTRACT_K8S_MINOR}\"" "${SCRIPT_DIR}/node-common.sh"; then
  echo "compatibility.json's kubernetes.bootstrap_pinned_minor (${CONTRACT_K8S_MINOR}) does not match bootstrap/node-common.sh's KUBERNETES_MINOR" >&2
  FAIL=1
fi
if ! grep -qF "image: ${CONTRACT_DASHBOARD_IMAGE}" "${LAB_DIR}/dashboard/headlamp-manifest.yaml"; then
  echo "compatibility.json's dashboard.image (${CONTRACT_DASHBOARD_IMAGE}) does not match dashboard/headlamp-manifest.yaml's image" >&2
  FAIL=1
fi
if ! grep -q "ubuntu-jammy-${CONTRACT_OS_RELEASE}-" "${LAB_DIR}/providers/aws/main.tf"; then
  echo "compatibility.json's os.release (${CONTRACT_OS_RELEASE}) does not match providers/aws/main.tf's Ubuntu AMI filters" >&2
  FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then
  echo "check_compatibility_contract: compatibility.json matches the bootstrap scripts' pinned versions"
fi
exit "$FAIL"
