# Kubernetes bootstrap deep-dive

This doc explains *how* `clusterdrill-lab` builds a Kubernetes cluster by hand, and *why* each
step is shaped the way it is - detailed enough that you could reproduce the same
control-plane/worker/CNI setup yourself on two fresh Ubuntu VMs, without ever running
`bootstrap/*.sh`.

It is not the same doc as [`bootstrap/README.md`](../bootstrap/README.md). That doc tells you how to
*run* the automation (`run.sh`, its arguments, its flow). This doc tells you how the automation
works internally and reasons about each step, so you can understand it or replicate it by hand.
It also isn't a copy of [`providers/aws/README.md`](../providers/aws/README.md)'s compatibility
matrix - version numbers live there and are linked from here, not repeated.

If you want the big-picture system map first (what provisions what, cloud-specific vs.
cloud-agnostic), see [`ARCHITECTURE.md`](ARCHITECTURE.md) (published as part of the sibling
architecture-overview work, issue #170). This doc picks up one level down: the inside of
`bootstrap/`.

## Order of operations

`bootstrap/run.sh` runs these steps, over SSH, in this order, against every node a
`providers/<cloud>/` module produced:

1. `node-common.sh` on **every** node (control-plane and workers alike).
2. `control-plane.sh` on the control-plane node only.
3. `worker.sh` on every worker node, once `control-plane.sh` has finished.
4. `deploy-appliance.sh` on the control-plane node, only after **every** worker has joined.
5. `deploy-headlamp.sh` on the control-plane node, right after the appliance.

Steps 4 and 5 are separate scripts run *after* every worker joins, not folded into
`control-plane.sh`, because both Deployments they create have no toleration for the
control-plane's own `NoSchedule` taint. In a real multi-node lab, either Deployment can only
schedule once a worker node actually exists to run on it - running them any earlier would just
hang until `kubectl rollout status`'s own timeout and fail. `bootstrap/README.md`'s "Flow" section
and `run.sh`'s own comments document this same reasoning; it's restated here because it's the key
fact that explains why this is five scripts instead of three.

The rest of this doc walks through what each step actually does, in the same order.

## 1. Prerequisites on the node (`node-common.sh`)

Runs identically on every node, before anything role-specific happens. Three things, in order.

The swap/kernel-module/sysctl steps below are distro-agnostic and run the same regardless of OS.
The containerd and kubelet/kubeadm/kubectl install steps are not: `node-common.sh` first calls
`detect_os_family` (`bootstrap/lib/os-family.sh`), which reads `/etc/os-release` and sources either
`bootstrap/lib/debian.sh` or `bootstrap/lib/rhel.sh` before calling `os_install_containerd` and
`os_install_kube_packages` - a shared function-name contract, one implementation per package-manager
family, rather than a distro check inline in this script. This walkthrough describes the
`debian.sh` path (`apt`-based Ubuntu/Debian), the one real cluster this project's own CI actually
bootstraps end to end - see [`bootstrap/README.md`](../bootstrap/README.md)'s "Known limitations" for
what level of verification the `rhel.sh` (`dnf`-based RHEL/Rocky/Fedora) path has instead.

**Swap is disabled.** `swapoff -a`, plus commenting out the swap line in `/etc/fstab` so it stays
off across a reboot. The kubelet refuses to start with swap enabled by default - this isn't a
performance tweak, it's a hard prerequisite.

**containerd is installed and configured as the container runtime.** Installed via `apt`, then
one deliberate edit to its generated default config: `SystemdCgroup` is flipped from `false` to
`true` in `/etc/containerd/config.toml`. This matters because kubelet's own default cgroup driver
is `systemd`, but containerd's default config ships with `SystemdCgroup = false` - left alone, the
mismatch doesn't fail loudly. The kubelet starts, but silently never reports `Ready`. The kernel
modules (`overlay`, `br_netfilter`) and sysctls (`net.bridge.bridge-nf-call-iptables`,
`net.bridge.bridge-nf-call-ip6tables`, `net.ipv4.ip_forward`) loaded before this are what kubeadm's
own preflight checks require: bridged traffic has to actually reach iptables for
`kube-proxy`/Cilium's own datapath rules to see it, and forwarding has to be on for a node to route
pod traffic at all.

**`kubelet`, `kubeadm`, and `kubectl` are installed from the `pkgs.k8s.io` apt repo, pinned to a
minor version, then held.** The repo path itself encodes the minor version:
`https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_MINOR}/deb/`, where `KUBERNETES_MINOR` is a
constant at the top of `node-common.sh`. Only the **minor** is pinned here - whatever patch
version that channel happens to serve on the day you install is what you get. That split (minor
pinned, patch floating) is deliberate and is spelled out in
[`compatibility.json`](../compatibility.json)'s `kubernetes.bootstrap_pinned_patch` field: pinning
the minor keeps every node in a given lab run on API versions this project has actually tested
against, while letting the patch float picks up routine security fixes automatically without this
project needing to bump a constant for every patch release. See
`providers/aws/README.md`'s [compatibility matrix](../providers/aws/README.md#compatibility-matrix)
for the exact minor currently pinned - it's linked here rather than repeated so this doc doesn't
go stale the next time that constant changes.

After install, `apt-mark hold kubelet kubeadm kubectl` freezes those three specific packages
against a routine `apt upgrade` jumping them to a different (and untested) Kubernetes version,
while every other package on the node still patches normally. `providers/aws/README.md`'s
[Patch/upgrade](../providers/aws/README.md#patch--upgrade) section covers what to do when you
actually want to move the pinned minor forward.

The whole script is written to be idempotent - safe to re-run if a partial bootstrap failed
partway through. The one non-obvious detail supporting that claim: the GPG dearmor step uses
`gpg --yes --batch --dearmor`, not a plain `--dearmor`. Without `--yes --batch`, gpg prompts
interactively to overwrite the keyring file if it already exists (e.g. a re-run, or a
pre-provisioned image that already ships this exact keyring) - and that prompt goes to `/dev/tty`,
which doesn't exist in a non-interactive SSH/CI invocation. Without the flags, a second run of this
"safe to re-run" script would simply hang.

## 2. Control-plane init (`control-plane.sh`)

Runs once `node-common.sh` has finished on the control-plane node. The first real step:

```sh
sudo kubeadm init --pod-network-cidr="$POD_CIDR" --apiserver-cert-extra-sans="$CONTROL_PLANE_IP"
```

**`--pod-network-cidr`** tells kubeadm which CIDR block pod IPs will come from, and it writes that
choice into cluster config that the CNI plugin reads later. `control-plane.sh` sets `POD_CIDR` to
`10.244.0.0/16` - a private RFC 1918 range picked specifically because it's the range Cilium's own
default installation docs assume and Cilium's IPAM otherwise expects, given nothing on this
project's side overrides it. Getting this flag and the CNI's own expectations out of sync is a
classic kubeadm footgun (pods scheduled but stuck with no IP, or on a completely wrong subnet) -
this project's version of that check is `cilium status --wait` at the end of this same script,
covered below.

**`--apiserver-cert-extra-sans`** is passed the control-plane's public IP (`$CONTROL_PLANE_IP`,
handed in by `run.sh` from the provider module's own Terraform output - never self-detected via a
cloud instance-metadata call, since that API's shape differs per cloud and would make this script
cloud-specific). Without this flag, kubeadm's generated API server certificate only covers the
addresses it can see locally at `init` time - typically the node's private IP and the in-cluster
service IP - and never the public IP an operator will actually connect to from their own machine
afterward. Adding the public IP as an extra Subject Alternative Name is what lets you later copy
`~/.kube/config` off the node, point its `server:` field at the public IP, and have TLS validation
still succeed. `providers/aws/README.md` documents [exactly that workflow](../providers/aws/README.md#headlamp-dashboard)
for reaching the cluster from your own machine instead of over SSH.

**Kubeconfig setup** is the standard kubeadm dance: copy `/etc/kubernetes/admin.conf` (written by
`kubeadm init`, root-owned) to `$HOME/.kube/config` for the operator user, then `chown` it to that
user so `kubectl` run as a normal user picks it up without `sudo`.

One escape hatch worth knowing about if you read the script: `CLUSTERDRILL_LAB_SINGLE_NODE=1`
strips the control-plane's default `NoSchedule` taint immediately after `init`, letting regular
workloads (including the appliance and dashboard, later) schedule directly onto the control-plane
node. This exists only for CI running this bootstrap flow on a single runner with no separate
worker at all (see `.github/workflows/lab-quality-gate.yml`'s `app-lab-compatibility-e2e` job) -
`variables.tf`'s `worker_count` validation requires at least one real worker for any actual lab,
so a real lab never needs this and shouldn't set it.

## 3. CNI install (`control-plane.sh`, continued)

Still in `control-plane.sh`, right after `kubeadm init` succeeds:

```sh
cilium install --version "$CILIUM_VERSION"
cilium status --wait
```

**Why Cilium specifically**, rather than any of the other CNCF-listed CNI plugins: the
practice-bank question set's networking questions are written assuming Cilium is the CNI in
place - `NetworkPolicy` behavior, and any Cilium-specific concepts the question bank exercises,
need Cilium's actual datapath underneath them to behave the way those questions expect. Swapping
in a different CNI would silently break that subset of questions rather than error out cleanly.

Before `cilium install` can run at all, the `cilium` CLI itself has to be present. `control-plane.sh`
detects the node's architecture (`uname -m`, mapped to `amd64` or `arm64`) and downloads the
matching `cilium-cli` release archive - this is what makes a mixed-architecture lab (e.g. an
amd64 control-plane with Graviton/arm64 workers) work without any manual intervention, since the
control-plane is where this CLI needs to run regardless of what architecture the workers end up
being.

**The pinned `CILIUM_VERSION`** (see `providers/aws/README.md`'s
[compatibility matrix](../providers/aws/README.md#compatibility-matrix) for the exact current value)
buys reproducibility: `cilium install` without a version pin installs whatever the CLI's own
default resolves to at install time, which can silently drift across lab runs weeks or months
apart. Pinning means every lab provisioned against this codebase gets the same Cilium behavior,
matching whatever version the practice-bank question set was actually written and verified
against.

**`cilium status --wait`** is not a fixed sleep or a single readiness check - it polls Cilium's own
in-cluster status (agent DaemonSet rollout, the operator Deployment, and Cilium's own internal
health checks) until Cilium reports itself fully operational, or fails outright if it can't reach
that state. Concretely, this is what lets `control-plane.sh` safely assume, the instant this line
returns, that pod networking is live enough for kubeadm's own subsequent steps (and the later
appliance/dashboard Deployments) to schedule and get real IP addresses - the same "-wait" contract
`deploy-appliance.sh`'s own `kubectl rollout status --timeout=5m` gives it for the appliance
Deployment later.

The last thing `control-plane.sh` does is generate the worker join credentials:

```sh
sudo kubeadm token create --print-join-command | sudo tee /tmp/kubeadm-join-command.sh
```

This is a **fresh bootstrap token** with its own `kubeadm join ...` invocation, written to a file
rather than only printed - `run.sh` `scp`s that exact file off the control-plane node and onto
every worker before running `worker.sh`, covered next.

## 4. Worker join (`worker.sh`)

Runs on each worker node, after `node-common.sh` has already installed the same
kubelet/kubeadm/kubectl/containerd stack there, and after `run.sh` has copied
`/tmp/kubeadm-join-command.sh` (produced by `control-plane.sh` above) onto that worker.

```sh
sudo bash /tmp/kubeadm-join-command.sh
```

That file expands to a `kubeadm join <control-plane-ip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>`
invocation. Unlike `kubeadm init`, `kubeadm join` doesn't create any new control-plane
components - it does three things: verifies the control-plane's identity using the discovery
token's CA cert hash (so a worker can't be tricked into joining an impostor cluster), registers
this node's `kubelet` with the API server, and lets the kubelet pull down the cluster's shared
configuration (CA data, cluster DNS, etc.) so it can start reporting node status and accepting
scheduled pods. A worker never runs `kubeadm init` and never runs a control-plane static pod
(no `kube-apiserver`, `etcd`, `kube-scheduler`, or `kube-controller-manager` on it) - it's a
Kubernetes worker-only join, not a second control-plane.

Once every worker has joined, `run.sh` moves on to the two Deployments that were waiting for this.

## 5. Appliance install (`deploy-appliance.sh`)

Run on the control-plane node, by `run.sh`, only after every `worker.sh` invocation has completed -
see [Order of operations](#order-of-operations) above for why the ordering matters.

At a high level: install a Python 3.11 environment via `pipx` (Ubuntu 22.04's default `python3` is
3.10, older than the `clusterdrill` package's `requires-python`), fetch the pinned release wheel
(public release URL first, falling back to the GitHub API with a supplied token while the app
repository is still private - see `bootstrap/README.md`'s
["Installing while the app repository is still private"](../bootstrap/README.md#installing-while-the-app-repository-is-still-private)
section for that mechanism), `pipx install` it, then resolve and apply its Kubernetes manifest.

**The pinned artifact.** `compatibility.json`'s `app.version` and `app.image_digest` are the
authoritative pin - `deploy-appliance.sh`'s own `CLUSTERDRILL_BOOTSTRAP_VERSION` constant must
match `app.version` exactly, and `bootstrap/check_compatibility_contract.sh` enforces that in CI
so the two can never silently drift apart. The image itself is resolved by digest, not just a
version tag, the same way the Minikube-based local-install path resolves it without an explicit
`--image` override.

**RBAC.** What ClusterRole/ClusterRoleBinding the appliance is granted, and why, is documented
once in `compatibility.json`'s `app.required_privileges` field (which itself points at
`practice-bank/clusterdrill/manifests/local-appliance.yaml`'s actual ClusterRole and
`practice-bank/README.md`'s Security limits section) - deliberately not restated here, so this doc
can't drift out of sync with the real manifest the way a second copy of an RBAC list always
eventually does.

**Why this step waits for workers.** The appliance's Deployment carries no toleration for the
control-plane's own `NoSchedule` taint (`node-role.kubernetes.io/control-plane`). A `Deployment`
with no matching toleration for a node's taint simply never schedules onto that node - it sits
`Pending` until a node without that taint (or with a taint it does tolerate) exists. In a real lab
with at least one worker, that's exactly the intended outcome: the appliance runs on a worker, not
on the control-plane. But it means running `deploy-appliance.sh` before any worker has joined
doesn't fail fast - it hangs until `kubectl -n clusterdrill-system rollout status deployment/clusterdrill-web --timeout=5m`
times out on its own five-minute clock and then fails. That's the reason this is a separate script
invoked after every worker join completes, rather than the tail end of `control-plane.sh` -
`bootstrap/README.md`'s "Flow" section and `run.sh`'s own comments document the same reasoning in
the context of running the automation; this is the same fact, explained here for someone building
the sequence by hand.

## 6. Dashboard install (`deploy-headlamp.sh`)

Run immediately after the appliance, for the same reason and under the same constraint: the
Headlamp Deployment also carries no toleration for the control-plane's `NoSchedule` taint, so it
too only schedules once a worker exists to run it. `run.sh` `scp`s
`dashboard/headlamp-manifest.yaml` to the control-plane node first (the same way it separately
copies the join-command file - transferring only the one script it's about to invoke, not files
that script references), then `deploy-headlamp.sh` simply `kubectl apply -f`s it and waits on its
own rollout the same way the appliance does.

RBAC scope is, again, defined once and linked rather than duplicated:
`compatibility.json`'s `dashboard.required_privileges` field, backed by
`dashboard/headlamp-manifest.yaml`'s own `ClusterRole` (`headlamp-viewer`) - a single read-only
(`get`/`list`/`watch`) ClusterRole covering the same resource kinds as the appliance's own
ClusterRole, including Secrets. That last point is a deliberate choice specific to this lab's
single-operator model, not an oversight: whoever runs this lab already has unrestricted `kubectl`
access over SSH, so excluding Secrets from the dashboard's read-only view would be a UI-only gap
with no real access-boundary benefit, while CKAD's own question set routinely involves Secrets.
The manifest also deliberately does *not* use Headlamp's own upstream Helm chart, whose default
install grants a full cluster-admin `ClusterRoleBinding` - this static manifest is the
narrower-scoped alternative.

## Appendix: doing this by hand

The sequence below is the manual equivalent of everything above, for two fresh Ubuntu 22.04 VMs
you provision yourself (one control-plane, one worker), with no `bootstrap/*.sh` involved.
Exact pinned version numbers (Kubernetes minor, Cilium version, cilium-cli version) are called out
above by name but not repeated here - pull the current values from
`providers/aws/README.md`'s [compatibility matrix](../providers/aws/README.md#compatibility-matrix)
and substitute them below, so this appendix doesn't go stale independently of that table. For any
step's full flag reference beyond what's shown here, follow the official docs this project itself
is written against:
[kubeadm install docs](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/),
[containerd runtime docs](https://kubernetes.io/docs/setup/production-environment/container-runtimes/),
[kubeadm upgrade docs](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/)
(for the patch/upgrade path, not initial bootstrap), and
[Cilium's install docs](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/) /
[Cilium's upgrade guide](https://docs.cilium.io/en/stable/operations/upgrade/) - all already linked
from `providers/aws/README.md`'s [Patch/upgrade](../providers/aws/README.md#patch--upgrade) section.

### On both VMs

```sh
# Disable swap, including across reboot
sudo swapoff -a
sudo sed -i '/\sswap\s/s/^/#/' /etc/fstab

# Kernel modules and sysctls kubeadm requires
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system

# containerd, with the systemd cgroup driver kubelet expects
sudo apt-get update
sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# kubelet/kubeadm/kubectl, pinned to the minor in providers/aws/README.md's
# compatibility matrix (substitute for <K8S_MINOR> below), then held
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
sudo mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v<K8S_MINOR>/deb/Release.key" \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v<K8S_MINOR>/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable kubelet
```

### On the control-plane VM only

```sh
# <CONTROL_PLANE_PUBLIC_IP>: this VM's public/SSH-reachable IP
sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-cert-extra-sans=<CONTROL_PLANE_PUBLIC_IP>

mkdir -p "$HOME/.kube"
sudo cp -f /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

# Install the cilium CLI - pick the archive matching this VM's architecture
# (amd64 or arm64) and the cilium-cli version in the compatibility matrix
curl -fsSL --output cilium-linux.tar.gz \
  "https://github.com/cilium/cilium-cli/releases/download/<CILIUM_CLI_VERSION>/cilium-linux-<amd64-or-arm64>.tar.gz"
sudo tar -xzf cilium-linux.tar.gz -C /usr/local/bin cilium
rm -f cilium-linux.tar.gz

# Install Cilium at the pinned version in the compatibility matrix, and wait
# for it to actually report healthy before doing anything else
cilium install --version <CILIUM_VERSION>
cilium status --wait

# Generate a join command for the worker
sudo kubeadm token create --print-join-command
```

Copy the exact output of that last command - it's the full `kubeadm join ...` invocation, tokens
and cert hash included.

### On the worker VM only

Paste the `kubeadm join ...` command from the control-plane step above, prefixed with `sudo`:

```sh
sudo kubeadm join <control-plane-ip>:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

### Verify

Back on the control-plane VM:

```sh
kubectl get nodes      # both nodes should show Ready once Cilium and kubelet agree
kubectl get pods -A    # kube-system pods and Cilium's own agent/operator pods should be Running
```

At this point you have a working two-node cluster with Cilium installed - the same state
`bootstrap/run.sh` reaches right before it hands off to `deploy-appliance.sh`. Installing the
`clusterdrill` appliance and Headlamp dashboard by hand from here follows the same reasoning laid
out in [Appliance install](#5-appliance-install-deploy-appliancesh) and
[Dashboard install](#6-dashboard-install-deploy-headlampsh) above, but is not repeated as a manual
command sequence here: both depend on artifacts (the pinned wheel, the Headlamp manifest) that are
this project's own build output rather than upstream commands, so "do it by hand" for those two
steps is really "read `bootstrap/deploy-appliance.sh` and `bootstrap/deploy-headlamp.sh` and adapt
them," not a generic recipe that stays useful outside this repository the way the kubeadm/Cilium
sequence above does.

**A note on how thoroughly this appendix was checked.** The command sequence above was checked for
internal consistency against the actual current `bootstrap/node-common.sh` and
`bootstrap/control-plane.sh` (flag names, file paths, and ordering all traced back to those
scripts directly) - but it has not been live-tested end to end against two freshly-provisioned
Ubuntu 22.04 VMs in this environment. If you try it and hit a gap, please open an issue.
