#!/usr/bin/env bash
# Installs the Helm and Kustomize CLI binaries for the operator's own CKAD
# practice use - nothing in bootstrap/ itself uses either tool internally
# (see ../../docs/BOOTSTRAP-DEEPDIVE.md's note on why Headlamp deploys via a
# static manifest, not its own upstream Helm chart; that decision is
# unrelated to and unchanged by this file).
#
# Deliberately NOT part of the os_install_* os-family dispatch contract
# (os-family.sh, debian.sh, rhel.sh) - neither tool has an officially-blessed
# apt/dnf package (Helm's own docs describe its apt/rpm repos as
# community-contributed, not the project's own method), so both install the
# same way regardless of distro family: a pinned-version release tarball,
# verified by its published SHA256 checksum, for whichever of amd64/arm64
# this node actually is. Sourced unconditionally by node-common.sh, the same
# way os-family.sh itself is.

# Exact current stable releases as of this file's writing - reverify against
# https://github.com/helm/helm/releases and
# https://github.com/kubernetes-sigs/kustomize/releases before bumping either,
# since both move independently of this repo's own release cycle. Helm v3's
# bug-fix window is already closed and its security-fix window closes only a
# couple of months after this file was written, so v4 (not v3) is the
# intentional pin here, not a default followed blindly.
HELM_VERSION="v4.2.4"
KUSTOMIZE_VERSION="v5.8.1"

# Every helm-vX.Y.Z-linux-<goarch>.tar.gz asset kubectl-adjacent tools ship
# under uses Go's own arch names, not `uname -m`'s - translate once here
# rather than in each of this file's two install functions.
#
# Duplicates the same uname-m-to-goarch mapping control-plane.sh has inline
# for its own Cilium CLI download (that script sources no lib/ file today,
# unlike node-common.sh/deploy-appliance.sh - unifying the two is a separate,
# larger refactor out of scope for this change). If either mapping's set of
# supported architectures ever changes, check the other one too.
_practice_tools_goarch() {
  case "$(uname -m)" in
    x86_64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *)
      echo "practice-tools: unsupported architecture ($(uname -m)) - this lab only supports amd64/arm64, matching providers/aws/variables.tf's control_plane_architecture/worker_architecture" >&2
      exit 1
      ;;
  esac
}

install_helm() {
  if command -v helm >/dev/null && [ "$(helm version --template '{{.Version}}' 2>/dev/null)" = "$HELM_VERSION" ]; then
    echo "node-common: helm ${HELM_VERSION} already installed, skipping"
    return
  fi

  echo "node-common: installing helm ${HELM_VERSION}"
  local goarch tarball
  goarch="$(_practice_tools_goarch)"
  tarball="helm-${HELM_VERSION}-linux-${goarch}.tar.gz"
  # Deliberately not `local` - an EXIT trap set inside a function can't see
  # that function's own local variables once bash starts unwinding it (true
  # even for a failure that originates inside this same function body, not
  # just after it returns - verified experimentally), so this has to be
  # visible at the same scope the trap fires in. Cleared and cleaned up
  # explicitly at the end of a successful run below; either function failing
  # aborts the whole script (`set -euo pipefail` in the sole caller,
  # node-common.sh) before the other one ever runs, so the two functions
  # never contend over this name.
  workdir="$(mktemp -d)"
  # Runs on every exit path, not just success - without it, a checksum
  # mismatch or a failed download leaks this directory (and its downloaded
  # tarball) under /tmp on every failed attempt. Same problem
  # deploy-appliance.sh already solves with its own EXIT trap for its
  # downloaded temp file.
  trap 'rm -rf "$workdir"' EXIT
  # get.helm.sh is Helm's own official binary distribution point - GitHub's
  # release assets for this project are detached PGP signatures only, never
  # the tarball itself.
  curl -fsSL -o "${workdir}/${tarball}" "https://get.helm.sh/${tarball}"
  curl -fsSL -o "${workdir}/${tarball}.sha256sum" "https://get.helm.sh/${tarball}.sha256sum"
  # Verified inside workdir, not the caller's cwd - sha256sum -c reads the
  # checksum file's own recorded filename relative to its current directory.
  (cd "$workdir" && sha256sum -c "${tarball}.sha256sum")
  tar -xzf "${workdir}/${tarball}" -C "$workdir"
  sudo install -m 0755 "${workdir}/linux-${goarch}/helm" /usr/local/bin/helm
  rm -rf "$workdir"
  trap - EXIT
}

install_kustomize() {
  if command -v kustomize >/dev/null && [ "$(kustomize version 2>/dev/null)" = "$KUSTOMIZE_VERSION" ]; then
    echo "node-common: kustomize ${KUSTOMIZE_VERSION} already installed, skipping"
    return
  fi

  echo "node-common: installing kustomize ${KUSTOMIZE_VERSION}"
  local goarch tarball base_url tarball_pattern
  goarch="$(_practice_tools_goarch)"
  tarball="kustomize_${KUSTOMIZE_VERSION}_linux_${goarch}.tar.gz"
  base_url="https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}"
  # See install_helm's own comment on why this one variable isn't `local`.
  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' EXIT
  curl -fsSL -o "${workdir}/${tarball}" "${base_url}/${tarball}"
  # checksums.txt covers every platform in this one release, not just
  # linux/$goarch - fetched separately from the filter below, so a failed
  # download (network error, GitHub outage, rate limit) gets its own clear
  # error here rather than being mistaken for the no-checksum-entry case
  # the filter step guards against next.
  if ! curl -fsSL -o "${workdir}/checksums-all.txt" "${base_url}/checksums.txt"; then
    echo "practice-tools: failed to download kustomize ${KUSTOMIZE_VERSION}'s checksums.txt from ${base_url}" >&2
    exit 1
  fi
  # Escape regex metacharacters (kustomize's own filenames are dot-heavy:
  # "kustomize_v5.8.1_linux_amd64.tar.gz") before using this as a grep
  # pattern - unescaped, those dots match any character, weakening the
  # "select exactly this platform's line" guarantee below to something grep
  # doesn't actually enforce.
  tarball_pattern="${tarball//./\\.}"
  # Filtered to this node's own line before verifying, so a mismatch on some
  # other platform's entry can never mask (or falsely trigger against) this
  # one.
  grep " ${tarball_pattern}\$" "${workdir}/checksums-all.txt" > "${workdir}/checksums.txt" || true
  # A no-match here (e.g. upstream renames its release asset) would leave
  # checksums.txt empty - `sha256sum -c` on an empty file exits 0 with
  # nothing checked, which would silently skip verification entirely rather
  # than fail loudly. Guard for that explicitly instead of relying on the
  # grep pipeline's own exit status to be enough.
  [ -s "${workdir}/checksums.txt" ] || {
    echo "practice-tools: no checksum entry for ${tarball} in kustomize ${KUSTOMIZE_VERSION}'s checksums.txt - refusing to install unverified" >&2
    exit 1
  }
  (cd "$workdir" && sha256sum -c checksums.txt)
  tar -xzf "${workdir}/${tarball}" -C "$workdir"
  sudo install -m 0755 "${workdir}/kustomize" /usr/local/bin/kustomize
  rm -rf "$workdir"
  trap - EXIT
}
