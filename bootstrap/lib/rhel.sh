#!/usr/bin/env bash
# RHEL-family (RHEL, Rocky, CentOS, AlmaLinux, Fedora) implementation of the
# os_install_* function contract - sourced by node-common.sh after
# detect_os_family (see os-family.sh) resolves to "rhel". Written fresh
# against the public kubeadm RPM install docs
# (https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)
# and Docker's own RPM install docs (https://docs.docker.com/engine/install/rhel/) -
# no text or structure copied from any private or course-provided script.
#
# Unlike debian.sh, this path isn't run in CI - it has been verified once,
# manually, against a real Rocky Linux 9 target - see ../README.md's "Known
# limitations" for the full account of that run, including the one real bug
# it caught (the exclude= line below).

# /etc/os-release's ID (rhel, rocky, centos, almalinux, fedora, ...) -
# os-family.sh already collapsed this down to the coarse "rhel" family, but
# the Docker repo URL forks on the exact distro within it.
_rhel_id() {
  # shellcheck disable=SC1091 # the real /etc/os-release, not a repo file -
  # unfollowable by shellcheck by design, this always runs on a real host.
  (. /etc/os-release && echo "$ID")
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
