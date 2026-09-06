#!/usr/bin/env bash
# Debian-family (Ubuntu, Debian) implementation of the os_install_* function
# contract - sourced by node-common.sh/deploy-appliance.sh after
# detect_os_family (see os-family.sh) resolves to "debian". This is the one
# family this repo's own CI actually runs as a real cluster
# (app-lab-compatibility-e2e in ../../.github/workflows/lab-quality-gate.yml)
# - keep this behavior-identical to what it replaces; any deviation here is a
# regression, not a stylistic choice.

os_install_containerd() {
  echo "node-common: installing containerd"
  sudo apt-get update -qq
  sudo apt-get install -y -qq containerd
  sudo mkdir -p /etc/containerd
  containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
  # kubelet's own default cgroup driver is systemd; containerd's default
  # config.toml ships with SystemdCgroup = false, which silently mismatches
  # and produces a kubelet that starts but never reports Ready.
  sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  sudo systemctl restart containerd
  sudo systemctl enable containerd >/dev/null
}

os_install_kube_packages() {
  local kubernetes_minor="$1"
  echo "node-common: installing kubelet, kubeadm, kubectl (v${kubernetes_minor})"
  sudo apt-get install -y -qq apt-transport-https ca-certificates curl gpg
  sudo mkdir -p /etc/apt/keyrings
  # --yes --batch: dearmor non-interactively even if the destination already
  # exists (e.g. a pre-provisioned image that already ships this exact
  # keyring) - without it, gpg prompts to overwrite via /dev/tty, which
  # doesn't exist in a non-interactive SSH/CI invocation, contradicting this
  # script's own "safe to re-run" claim.
  curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${kubernetes_minor}/deb/Release.key" \
    | sudo gpg --yes --batch --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${kubernetes_minor}/deb/ /" \
    | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq kubelet kubeadm kubectl
  sudo apt-mark hold kubelet kubeadm kubectl >/dev/null

  sudo systemctl enable kubelet >/dev/null
}

os_install_appliance_python_deps() {
  # The clusterdrill package requires Python >= 3.11 (pyproject.toml's
  # requires-python), but Ubuntu 22.04's own default system python3 is 3.10
  # - installing it explicitly and pointing pipx at it, rather than
  # whatever `python3` resolves to, keeps this working on the documented
  # Ubuntu 22.04 target (see ../../compatibility.json's os.release) without
  # depending on the distro's own default ever changing.
  sudo apt-get install -y -qq python3-pip python3.11 python3.11-venv pipx
  CLUSTERDRILL_PYTHON_BIN="python3.11"
  export CLUSTERDRILL_PYTHON_BIN
  pipx ensurepath
  export PATH="$HOME/.local/bin:$PATH"
  # Ubuntu 22.04's apt-shipped pipx is 1.0.0, which predates the `pipx
  # environment` subcommand (added in 1.1.0) deploy-appliance.sh relies on to
  # locate pipx's own venv directory without hardcoding a path. Upgrade it
  # via pip - decoupled from the python3.11 pinned above, pipx itself just
  # needs to be new enough, not tied to any particular managed venv's
  # interpreter.
  python3 -m pip install --user --quiet --upgrade pipx
}
