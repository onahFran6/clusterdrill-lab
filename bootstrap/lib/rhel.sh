#!/usr/bin/env bash
# RHEL-family (RHEL, Rocky, CentOS, AlmaLinux, Fedora) implementation of the
# os_install_* function contract - sourced by node-common.sh/
# deploy-appliance.sh after detect_os_family (see os-family.sh) resolves to
# "rhel". Written fresh against the public kubeadm RPM install docs
# (https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)
# and Docker's own RPM install docs (https://docs.docker.com/engine/install/rhel/) -
# no text or structure copied from any private or course-provided script.
#
# Unlike debian.sh, this path has no real cluster behind it yet - see
# ../README.md's "Known limitations" for exactly what level of verification
# it has (shellcheck + the pure detect_os_family unit test, not a real
# kubeadm run). Fedora is the least-verified member of this family bucket:
# it shares dnf/RPM with RHEL/Rocky but not their repo layout (no EPEL/CRB
# needed on Fedora, and Fedora's default python3 may already be >= 3.11
# depending on release - see os_install_appliance_python_deps below).

# /etc/os-release's ID (rhel, rocky, centos, almalinux, fedora, ...) -
# os-family.sh already collapsed this down to the coarse "rhel" family, but
# EPEL/CRB and the Docker repo URL both fork on the exact distro within it.
_rhel_id() {
  # shellcheck disable=SC1091 # the real /etc/os-release, not a repo file -
  # unfollowable by shellcheck by design, this always runs on a real host.
  (. /etc/os-release && echo "$ID")
}

# RHEL/Rocky/CentOS/AlmaLinux need EPEL (and, on version 9+, the CRB repo
# EPEL itself depends on for some packages) enabled explicitly; Fedora ships
# everything this file needs in its default repos already.
_rhel_needs_epel() {
  [ "$(_rhel_id)" != "fedora" ]
}

_rhel_ensure_epel() {
  if _rhel_needs_epel && [ ! -f /etc/yum.repos.d/epel.repo ]; then
    echo "node-common: enabling EPEL/CRB"
    sudo dnf install -y epel-release
    sudo dnf config-manager --set-enabled crb || true
  fi
}

os_install_containerd() {
  echo "node-common: installing containerd"
  local docker_repo_os
  # download.docker.com has no separate Rocky/AlmaLinux/CentOS repo - they
  # all consume the same rhel one.
  docker_repo_os="rhel"
  [ "$(_rhel_id)" = "fedora" ] && docker_repo_os="fedora"

  sudo dnf install -y dnf-plugins-core
  sudo dnf config-manager --add-repo "https://download.docker.com/linux/${docker_repo_os}/docker-ce.repo"
  sudo dnf install -y containerd.io
  sudo mkdir -p /etc/containerd
  containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
  # Same kubelet/containerd cgroup-driver mismatch as debian.sh - see its
  # own comment on this exact line for why.
  sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  sudo systemctl restart containerd
  sudo systemctl enable containerd >/dev/null
}

os_install_kube_packages() {
  local kubernetes_minor="$1"
  echo "node-common: installing kubelet, kubeadm, kubectl (v${kubernetes_minor})"
  cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo >/dev/null
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${kubernetes_minor}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${kubernetes_minor}/rpm/repodata/repomd.xml.key
EOF
  sudo dnf install -y kubelet kubeadm kubectl

  # dnf's native equivalent of apt-mark hold - stops a later generic `dnf
  # upgrade` from moving these packages off the pinned minor, without
  # depending on a separate versionlock plugin package. Added to the repo
  # file only *after* the install above, not in the same heredoc: unlike
  # apt-mark hold (a separate step that only affects future upgrades),
  # dnf's `exclude=` filters that repo for every operation against it,
  # including a plain `dnf install` - present during the install itself,
  # it silently filters out the very packages being requested ("all
  # matches were filtered out by exclude filtering").
  echo "exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni" \
    | sudo tee -a /etc/yum.repos.d/kubernetes.repo >/dev/null

  sudo systemctl enable kubelet >/dev/null
}

os_install_appliance_python_deps() {
  _rhel_ensure_epel

  # Unlike Ubuntu 22.04's fixed "system python3 is 3.10" situation,
  # RHEL-family releases vary: RHEL/Rocky 9's default python3 is 3.9
  # (needs an explicit side-by-side python3.11 install), while Fedora's
  # default python3 is often already >= 3.11 depending on release (where
  # a hardcoded `dnf install python3.11` package may not even exist under
  # that exact name). Detect rather than assume.
  local system_minor
  system_minor="$(python3 -c 'import sys; print(sys.version_info[1])' 2>/dev/null || echo 0)"
  if [ "$system_minor" -ge 11 ]; then
    CLUSTERDRILL_PYTHON_BIN="python3"
  else
    sudo dnf install -y python3.11
    CLUSTERDRILL_PYTHON_BIN="python3.11"
  fi
  export CLUSTERDRILL_PYTHON_BIN

  # pipx: Fedora's default repos carry it; RHEL/Rocky need EPEL, already
  # enabled above.
  sudo dnf install -y pipx
  pipx ensurepath
  export PATH="$HOME/.local/bin:$PATH"
}
