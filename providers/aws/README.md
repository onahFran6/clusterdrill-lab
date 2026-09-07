# providers/aws

Provisions a disposable Kubernetes lab on AWS: one control-plane node, one
or more worker nodes, and the VPC/subnet/security-group/key-pair each
needs to exist and be reachable over SSH. This module's job stops there -
it does **not** install Kubernetes itself. See [`../../bootstrap/`](../../bootstrap/)
for the cloud-agnostic step that does, once this module hands it the
node IPs - or [`../../docs/BOOTSTRAP-DEEPDIVE.md`](../../docs/BOOTSTRAP-DEEPDIVE.md)
for a narrative walkthrough of how that bootstrap builds the cluster,
detailed enough to reproduce by hand.

## Cost

This provisions real, billed AWS resources (EC2 instances, EBS volumes,
a VPC and its networking). Nothing here is free-tier-guaranteed. You are
responsible for your own AWS costs, including destroying the lab when
you're done - see [Destroying the lab](#destroying-the-lab) below. There
is no cheaper "pause it overnight" option - see
[Pausing instead of destroying](#pausing-instead-of-destroying) for why.
`clusterdrill-lab` ships no automated cost control - see the root
[`README.md`](../../README.md)'s cost section for why.

## Prerequisites

- An AWS account and credentials Terraform can use (e.g. `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`,
  or an AWS CLI profile) with permission to create VPCs, EC2 instances,
  security groups, and key pairs.
- Terraform >= 1.5.0.
- Your own SSH key pair - this module never generates or holds a private
  key for you.

## Usage

```sh
cd providers/aws
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: your SSH public key, your IP's /32 for allowed_ssh_cidr

terraform init
terraform plan
terraform apply
```

### Configuration reference

Every variable in [`variables.tf`](variables.tf), what it defaults to, and why you'd change it:

| Variable | Default | Why you'd change it |
| --- | --- | --- |
| `aws_region` | `us-east-1` | Provision closer to you, or in a region where your account has capacity/pricing for the instance types below. |
| `cluster_name` | `clusterdrill-lab` | Give it a unique value to run more than one lab at once in the same account/region - it prefixes every resource name and tag. |
| `worker_count` | `1` | Bump it for practice questions that assume more than one worker (must be >= 1). |
| `control_plane_instance_type` | `t3.medium` | kubeadm's own minimum is 2 vCPU / 2 GiB; this is the tested default. |
| `worker_instance_type` | `t3.medium` | Same, per worker. |
| `control_plane_architecture` | `amd64` | Set to `arm64` for a Graviton instance type (e.g. `t4g.medium`) - must match the actual architecture of `control_plane_instance_type`. |
| `worker_architecture` | `amd64` | Same, for `worker_instance_type` - control-plane and workers may differ (a mixed-architecture lab is supported). |
| `ssh_public_key` | none, required | Your own SSH public key - this module never generates or holds a private key. |
| `allowed_ssh_cidr` | none, required | CIDR allowed to reach SSH/the Kubernetes API/NodePorts - deliberately has no default so you choose it, and can't be `0.0.0.0/0`. |
| `vpc_cidr` | `10.42.0.0/16` | Avoid a collision with a network you already use, or give a second lab a non-overlapping range. |
| `public_subnet_cidr` | `10.42.1.0/24` | Same, for the subnet - must stay a sub-range of `vpc_cidr`. |
| `availability_zone` | none - first AZ available | Pin a specific AZ, e.g. for capacity/pricing on a particular instance type. |
| `root_volume_size_gb` | `30` | More headroom for pulled container images, if you're running many practice questions in one lab without destroying it. |
| `root_volume_type` | `gp3` | Match your own cost/performance preference for the EBS volume. |
| `tags` | `{}` | Extra tags merged onto every resource, e.g. for your own cost-allocation tagging scheme. |

The Kubernetes minor version, Cilium version, and pod network CIDR are deliberately **not**
variables - see the Compatibility matrix below.

Then hand the outputs to the bootstrap step:

```sh
terraform output -json > ../../bootstrap/outputs.json
cd ../../bootstrap
./run.sh outputs.json ~/.ssh/id_ed25519   # your private key, paired with ssh_public_key above
```

If the app repository is still private, `run.sh` takes a third argument -
see [`../../bootstrap/README.md`](../../bootstrap/README.md#installing-while-the-app-repository-is-still-private).

`run.sh` prints a login password near the end of its output - keep it,
you'll need it for the appliance's web UI.

## Verifying the lab

`run.sh` itself already prints the SSH command and the Headlamp dashboard's URL at the end of a
successful run - see `bootstrap/README.md`'s ["What `run.sh` prints when it finishes"](../../bootstrap/README.md#what-runsh-prints-when-it-finishes).
The steps below are for manually verifying the lab, or for the `clusterdrill` appliance
specifically, which isn't included in that summary yet (see the same section for why).

From your own machine:

```sh
ssh -i ~/.ssh/id_ed25519 ubuntu@$(terraform -chdir=providers/aws output -raw control_plane_ip)
kubectl get nodes                              # every node should be Ready
kubectl -n clusterdrill-system get pods         # clusterdrill-web should be Running
kubectl -n clusterdrill-system get svc clusterdrill      # find the assigned NodePort
```

The appliance is reachable at `http://<control_plane_ip>:<nodeport>` -
log in with the password `run.sh` printed. The security group's
`nodeport_range` rule (30000-32767, restricted to your `allowed_ssh_cidr`)
already permits this from your own IP; nothing further to open.

### Headlamp dashboard

A [Headlamp](https://github.com/kubernetes-sigs/headlamp) dashboard is deployed alongside the
appliance, in its own `headlamp-system` namespace:

```sh
kubectl -n headlamp-system get svc headlamp   # find its assigned NodePort
kubectl create token headlamp -n headlamp-system --duration=8h
```

Reachable the same way as the appliance, at `http://<control_plane_ip>:<headlamp_nodeport>` -
same security group rule, nothing further to open. Log in with the token the command above
prints - Headlamp tokens are short-lived by design, so `deploy-headlamp.sh` never prints one
itself; generate a fresh one whenever you need it. It has read-only access to the whole
cluster, including Secrets - see `dashboard/headlamp-manifest.yaml`'s own ClusterRole comment
for why that's the deliberate choice for this single-operator lab.

To use `kubectl` from your own machine instead of over SSH, copy
`~/.kube/config` off the control-plane node and edit its `server:` line
from the node's private IP to `https://<control_plane_ip>:6443` - the
public IP is already a valid SAN on the API server's certificate (see
`control-plane.sh`'s `--apiserver-cert-extra-sans`), it's just not what
kubeadm writes into the config by default.

## Destroying the lab

```sh
cd providers/aws
terraform destroy
```

This is a disposable lab, not a persistent environment - destroy it
between sessions rather than leaving it running. `terraform destroy`
removes every resource this module created (instances, EBS volumes,
security group, key pair, VPC and its networking) and nothing else in
your AWS account.

### Pausing instead of destroying

There's no supported "pause for the night, resume tomorrow" option here - only destroy and
recreate. This module doesn't allocate an Elastic IP; each node's public IP
(`associate_public_ip_address = true`) is only guaranteed stable while the instance keeps
running. `aws ec2 stop-instances` looks like a cheaper pause (no EC2 compute charges while
stopped, only EBS storage), but stopping and starting reassigns a **new** public IP on start -
and `control-plane.sh` baked the *old* one into the API server's certificate
(`--apiserver-cert-extra-sans`) at `kubeadm init` time. After a stop/start, SSH still works fine
(a new IP, but still reachable), but `kubectl` from your own machine against the public IP fails
TLS validation, and `outputs.json`/anything else that cached the old IP is stale. Recovering from
that (re-issuing the cert, or just re-copying `~/.kube/config` and using the node's private IP
instead) is more effort than `terraform destroy` + a fresh `terraform apply` costs in practice,
for a lab meant to be disposable anyway - so this module doesn't try to support it.

## Recovery

**A node stops responding (SSH times out, `kubectl` hangs).** Check the
instance's status in the AWS console or `aws ec2 describe-instance-status`
first - a `2/2 checks passed` instance that still won't respond to SSH
is a kernel/network-stack issue inside the VM, not a Terraform problem.
Reboot it (`aws ec2 reboot-instances --instance-ids <id>`, or the console)
before reaching for anything more drastic. If reboot doesn't recover it,
treat the node as lost - see "Replacing a single node" below.

**Bootstrap failed partway through, for a reason unrelated to kubeadm itself** (a dropped SSH
session, a later step failing, `terraform apply` needing a second run first). `node-common.sh`,
`control-plane.sh`, and `worker.sh` are all written to be idempotent - each checks whether it
already succeeded (`/etc/kubernetes/admin.conf` on the control plane, `/etc/kubernetes/kubelet.conf`
on a worker) and skips straight past `kubeadm init`/`kubeadm join` if so. Simply re-running
`run.sh` (or the individual script against a single node, over SSH) resumes from wherever it
stopped, rather than failing on a "already initialized" error.

**`kubeadm init`/`kubeadm join` itself failed or left a node's kubeadm state genuinely broken**
(not just "already succeeded," but a real partial/corrupt init) - the idempotency check above
won't skip past a broken state cleanly, since it only checks for success, not health. Recovery is
`sudo kubeadm reset -f` on the affected node, then re-run the relevant `bootstrap/*.sh` step
(`control-plane.sh` or `worker.sh`) against it.

**Replacing a single node** (one worker died, the rest of the cluster is
fine): `terraform apply` after changing nothing will not recreate a node
you deleted out-of-band in the AWS console - Terraform only reconciles
resources it still tracks in state. If you terminated a node manually,
either `terraform apply` (which will notice the resource is gone and
recreate it, since Terraform's state still references it) or
`terraform state rm` it first if you want Terraform to fully forget it.
After Terraform recreates the instance, re-run `bootstrap/worker.sh`
against just that node's new IP to rejoin it - `run.sh` re-reading all
of `terraform output -json` will include the new IP automatically.

## State loss

If `terraform.tfstate` is lost (this module has no configured remote
backend by default - state lives in the local `providers/aws/` directory
unless you add one yourself), Terraform no longer knows what it created
and can't safely reconcile. For a lab this size and disposable by design,
the realistic recovery is not state surgery (`terraform import` for
every resource) - it's:

1. Manually terminate the orphaned resources in the AWS console (search
   by the `clusterdrill-lab` name tag / your `cluster_name`).
2. Delete the stale `terraform.tfstate*` files.
3. `terraform apply` again from a clean state to provision a fresh lab.

If you want state loss to not be a recovery scenario at all, configure a
remote backend (S3 + DynamoDB locking, Terraform Cloud, etc.) in your own
`terraform.tfvars`/backend config before the first `apply` - this module
intentionally ships with no backend configured, since which remote
backend (and its own cost/credentials) is an operator choice, not
something this lab should decide for you.

## Patch / upgrade

**OS packages.** `node-common.sh` installs `containerd`, `kubelet`,
`kubeadm`, and `kubectl` via `apt`, then `apt-mark hold`s the three
Kubernetes packages (so a routine `apt upgrade` won't silently jump you
to an untested Kubernetes version). To patch the underlying OS, SSH in
and run the normal `apt update && apt upgrade` - `apt-mark hold` only
protects the held packages.

**Kubernetes minor version.** This lab provisions a single control-plane
node, so kubeadm's node-by-node upgrade dance (`kubeadm upgrade plan`,
drain, `kubeadm upgrade apply`/`node`, uncordon, repeat per node) still
applies, but for a two-or-three-node disposable lab it's usually simpler
and no slower to `terraform destroy` and re-provision at the new
`KUBERNETES_MINOR` (edit that constant in
[`../../bootstrap/node-common.sh`](../../bootstrap/node-common.sh)) than
to live-upgrade a cluster you were going to tear down after the study
session anyway. If you do want to upgrade in place, follow the
[official kubeadm upgrade docs](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/)
directly - this project doesn't script that flow.

**Cilium version.** Re-run `cilium install --version <new-version>`
(see [`control-plane.sh`](../../bootstrap/control-plane.sh)'s
`CILIUM_VERSION`) - the `cilium` CLI handles in-place upgrades. Check
the [Cilium upgrade guide](https://docs.cilium.io/en/stable/operations/upgrade/)
for version-skip limits before jumping more than one minor version.

## Backup

This lab intentionally has no backup or snapshot automation - see
[What this module does not do](#what-this-module-does-not-do). If you
want to preserve something across a `destroy`/re-`apply` cycle, back it
up yourself before destroying:

- **Practice-bank progress/state** lives wherever the `clusterdrill`
  package's own local state does inside the cluster (see the
  practice-bank repository's own docs) - it is not this lab's concern to
  export it.
- **etcd** (if you want the full cluster state, not just practice-bank
  progress): `etcdctl snapshot save` against the control-plane node's
  etcd, per the [Kubernetes etcd backup docs](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/#backing-up-an-etcd-cluster).
  For a disposable practice lab this is almost always more effort than
  it's worth - re-provisioning from scratch is the intended, tested
  path.

## Compatibility matrix

| Component | Version | Pinned? |
| --- | --- | --- |
| OS | Ubuntu 22.04 LTS (Jammy) | Yes, deliberately - AMI filter in `main.tf`, not a variable. `deploy-appliance.sh` depends on 22.04-specific details (its system Python and apt-shipped pipx version); `compatibility.json`'s `os.release` records the same pin and `check_compatibility_contract.sh` fails if the two drift apart. |
| Architecture | amd64 or arm64, per node role | Yes - `control_plane_architecture`/`worker_architecture` each select their own Ubuntu 22.04 AMI; defaults to amd64. A mixed lab (e.g. amd64 control-plane, Graviton workers) is supported - the published `clusterdrill` appliance image is a multi-arch manifest, and `bootstrap/control-plane.sh` already resolves the Cilium CLI's architecture dynamically |
| Kubernetes (kubelet/kubeadm/kubectl) | 1.33.x | Minor pinned (`KUBERNETES_MINOR` in `node-common.sh`); exact patch is whatever `pkgs.k8s.io`'s `stable:/v1.33` channel resolves to at install time |
| containerd | Ubuntu 22.04's `containerd` apt package | Not pinned - whatever version Ubuntu's own apt repos serve at install time |
| Cilium | 1.16.5 | Yes - `CILIUM_VERSION` in `control-plane.sh` |
| cilium-cli | v0.16.16 | Yes - `CILIUM_CLI_VERSION` in `control-plane.sh` |
| Helm | Not applicable | No Helm chart exists yet for the `clusterdrill` package (a separate, not-yet-built distribution path) |
| Terraform | >= 1.5.0 | Minimum version constraint in `versions.tf`, not an exact pin |
| `hashicorp/aws` provider | ~> 5.0 | Constraint in `versions.tf`; exact resolved version is in the committed `.terraform.lock.hcl` |

Untested combinations (a different Ubuntu release, a different
Kubernetes minor, ARM instance types) are not guaranteed to work - this
matrix documents what this module and `bootstrap/` are actually written
and tested against, not a general compatibility promise.

## What this module does not do

- It does not manage DNS, TLS certificates, or any ingress beyond what
  the security group opens (SSH, the Kubernetes API, and the NodePort
  range, all restricted to `allowed_ssh_cidr`).
- It does not implement any budget alert, automated shutdown, or cost
  cap - see [Cost](#cost).
- It does not back up or snapshot anything - see [Backup](#backup).
- It does not configure a remote Terraform backend - see
  [State loss](#state-loss).

## Not for production use

This module provisions a single-control-plane, no-HA, no-backup,
no-automated-recovery cluster with a security group scoped to one
operator's own CIDR. It is a disposable CKAD practice lab, not a
production reference architecture - do not point real workloads or
production traffic at anything this module creates.

## Ownership

You own the AWS account, the credentials Terraform uses, the SSH key
pair, and the Terraform state this module produces. This project holds
none of these on your behalf, generates no credentials for you, and has
no visibility into your account - see
[Prerequisites](#prerequisites) and the SSH key note there.
