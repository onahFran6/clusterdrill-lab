# providers/aws

Provisions a disposable Kubernetes lab on AWS: one control-plane node, one
or more worker nodes, and the VPC/subnet/security-group/key-pair each
needs to exist and be reachable over SSH. This module's job stops there -
it does **not** install Kubernetes itself. See [`../../bootstrap/`](../../bootstrap/)
for the cloud-agnostic step that does, once this module hands it the
node IPs.

## Cost

This provisions real, billed AWS resources (EC2 instances, EBS volumes,
a VPC and its networking). Nothing here is free-tier-guaranteed. You are
responsible for your own AWS costs, including destroying the lab when
you're done - see [Destroying the lab](#destroying-the-lab) below.
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

## Recovery

**A node stops responding (SSH times out, `kubectl` hangs).** Check the
instance's status in the AWS console or `aws ec2 describe-instance-status`
first - a `2/2 checks passed` instance that still won't respond to SSH
is a kernel/network-stack issue inside the VM, not a Terraform problem.
Reboot it (`aws ec2 reboot-instances --instance-ids <id>`, or the console)
before reaching for anything more drastic. If reboot doesn't recover it,
treat the node as lost - see "Replacing a single node" below.

**`kubeadm init`/`kubeadm join` failed partway through bootstrap.**
`node-common.sh` is written to be idempotent (safe to re-run), but
`kubeadm init`/`kubeadm join` themselves are not - a second `kubeadm init`
on an already-initialized node fails loudly rather than silently
re-running. Recovery is `sudo kubeadm reset -f` on the affected node,
then re-run the relevant `bootstrap/*.sh` step (`control-plane.sh` or
`worker.sh`) against it. `run.sh` runs each step over SSH, so you can
target a single node manually if you don't want to re-run the whole
fleet.

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
| OS | Ubuntu 22.04 LTS (Jammy) | Yes - AMI filter in `main.tf` |
| Architecture | x86_64/amd64 only | Yes - AMI filter is amd64-only; no arm64/Graviton support today |
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
