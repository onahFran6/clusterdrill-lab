#!/usr/bin/env bash
# Unit-tests lib/os-family.sh's detect_os_family against synthetic
# /etc/os-release fixtures - the one part of the RHEL-family bootstrap path
# that's verified by a real, runnable test rather than just review, since
# there's no real RHEL-family cluster run in CI to exercise the rest of it
# (see ../bootstrap/README.md's "Known limitations"). Run from
# clusterdrill-lab/bootstrap/ or pass its own directory as $1.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/lib/os-family.sh
source "${SCRIPT_DIR}/lib/os-family.sh"

FIXTURE_DIR="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

FAIL=0

# $1: case name (for output only)
# $2: os-release content (ID=... and optionally ID_LIKE=...)
# $3: expected result - "debian", "rhel", or "fail"
check_case() {
  local name="$1" content="$2" expected="$3" fixture actual
  fixture="${FIXTURE_DIR}/${name}"
  printf '%s\n' "$content" > "$fixture"

  if actual="$(detect_os_family "$fixture" 2>/dev/null)"; then
    if [ "$expected" = "fail" ]; then
      echo "check_os_family_detection: ${name}: expected detect_os_family to fail, it returned '${actual}'" >&2
      FAIL=1
    elif [ "$actual" != "$expected" ]; then
      echo "check_os_family_detection: ${name}: expected '${expected}', got '${actual}'" >&2
      FAIL=1
    fi
  elif [ "$expected" != "fail" ]; then
    echo "check_os_family_detection: ${name}: expected '${expected}', detect_os_family failed instead" >&2
    FAIL=1
  fi
}

check_case "ubuntu"    'ID=ubuntu
ID_LIKE=debian'                    "debian"
check_case "debian"    'ID=debian'                          "debian"
check_case "rocky"     'ID=rocky
ID_LIKE="rhel centos fedora"'      "rhel"
check_case "fedora"    'ID=fedora'                          "rhel"
check_case "centos"    'ID=centos
ID_LIKE="rhel fedora"'             "rhel"
check_case "almalinux" 'ID=almalinux
ID_LIKE="rhel centos fedora"'      "rhel"
check_case "unsupported" 'ID=alpine
ID_LIKE=""'                        "fail"

if [ "$FAIL" -eq 0 ]; then
  echo "check_os_family_detection: all cases passed"
fi
exit "$FAIL"
