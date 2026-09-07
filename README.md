# ClusterDrill Lab

A disposable, provider-pluggable Kubernetes lab: Terraform provisions
the VMs, a cloud-agnostic bootstrap installs Kubernetes (kubeadm,
containerd, and Cilium) and the [`clusterdrill`](https://github.com/onahFran6/clusterdrill)
practice-bank appliance on top. Written clean-room against public
documentation - no code, text, or account-specific configuration
copied from any private or course-provided source.

## The `clusterdrill` practice bank

This lab exists to run [`clusterdrill`](https://github.com/onahFran6/clusterdrill) - the actual
CKAD practice bank: the question set, grading CLI, appliance image, and Helm chart. This repository
only provisions the infrastructure and installs a pinned `clusterdrill` release on top (see
[`compatibility.json`](compatibility.json) for the exact version) - it holds none of the
practice-bank's own questions or grading logic. If you're looking for the question set itself, or
want to run `clusterdrill` locally via Minikube instead of a full cloud lab, that's in the
`clusterdrill` repository, not here.

## Structure

```text
clusterdrill-lab/
  providers/
    aws/        Terraform root module - provisions the VMs (built first)
    gcp/        reserved seam, not built
  bootstrap/    cloud-agnostic: kubeadm, containerd, Cilium, clusterdrill
  dashboard/    Headlamp web dashboard, deployed by bootstrap alongside clusterdrill
  docs/         whole-system architecture and bootstrap deep-dive docs
  LICENSE       MIT
```

See [`providers/README.md`](providers/README.md) for the output contract
that connects the two, and [`bootstrap/README.md`](bootstrap/README.md)
for the bootstrap flow itself. See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for
a diagrammed overview of the whole system before diving into either, and
[`docs/BOOTSTRAP-DEEPDIVE.md`](docs/BOOTSTRAP-DEEPDIVE.md) for a narrative walkthrough
of how that bootstrap actually builds the cluster, detailed enough to
reproduce by hand. [`docs/README.md`](docs/README.md) is the full reading order for
every doc in this repository, in the order a new developer should go through them.

## Quick start (AWS)

Clone a tagged release rather than `main`, so what you provision matches a known-good, versioned
snapshot of this repository instead of whatever's newest on the default branch. See
[Releases](https://github.com/onahFran6/clusterdrill-lab/releases) for the latest tag - substitute
it for `clusterdrill-lab-v0.1.0` below.

```sh
git clone --branch clusterdrill-lab-v0.1.0 --depth 1 \
  https://github.com/onahFran6/clusterdrill-lab.git
cd clusterdrill-lab/providers/aws
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars` has working defaults for everything except two values, which have none on
purpose - Terraform will refuse to `apply` until you set them:

- **`ssh_public_key`** - your own SSH *public* key (never your private key). Don't have one yet?
  `ssh-keygen -t ed25519 -C "you@example.com"` (accept the default path), then get its contents
  with `cat ~/.ssh/id_ed25519.pub` and paste the whole line in.
- **`allowed_ssh_cidr`** - the CIDR allowed to reach the lab over SSH, the Kubernetes API, and
  NodePorts. For just your own current IP: `curl -s https://checkip.amazonaws.com`, then append
  `/32` (e.g. `203.0.113.4/32`). It can't be `0.0.0.0/0` - the variable's validation rejects that.

Everything else (region, instance size, architecture, and more) has a tested default - see
[`providers/aws/README.md`](providers/aws/README.md#configuration-reference) for the full
variable reference if you want to change any of it.

```sh
terraform init
terraform apply

terraform output -json > ../../bootstrap/outputs.json
cd ../../bootstrap
./run.sh outputs.json ~/.ssh/id_ed25519   # the private key paired with ssh_public_key above
```

See [`providers/aws/README.md`](providers/aws/README.md) for
prerequisites, cost information, and the full lifecycle runbook (destroy,
recovery, state loss, patch/upgrade, backup, and a compatibility matrix).

## Dashboard

Every lab comes with a [Headlamp](https://github.com/kubernetes-sigs/headlamp)
web dashboard into the cluster, deployed automatically as part of the
standard bootstrap - not a separate step. It's RBAC-aware and read-only
(including Secrets, since this is a single-operator lab where the
operator already has unrestricted `kubectl` access over SSH). See
[`bootstrap/README.md`](bootstrap/README.md#flow) for how it fits into
the bootstrap flow, and
[`providers/aws/README.md`](providers/aws/README.md#headlamp-dashboard)
for how to reach it and log in.

## Lifecycle and ownership

This is a disposable practice lab, not a production reference
architecture or a persistent environment - provision it, use it, destroy
it. You own the cloud account, credentials, SSH key pair, and Terraform
state; this project holds none of these on your behalf. See
[`providers/aws/README.md`](providers/aws/README.md#recovery) for what to
do if a node stops responding, state is lost, or you need to
patch/upgrade a running lab, and its
["Not for production use"](providers/aws/README.md#not-for-production-use)
section for the full disclaimer.

## Cost

This provisions real, billed cloud resources. You are responsible for
your own cloud costs, including destroying the lab when you're done.
This project ships no automated cost control, budget alert, or
auto-shutdown - see [`providers/aws/README.md`](providers/aws/README.md#cost).
Building that kind of automation as a portable public product feature is
a deliberate non-goal: an operator's cost tooling is tied to their own
account and billing setup in ways that don't generalize.

## Licensing

Everything in this repository is MIT-licensed - see [`LICENSE`](LICENSE).
Unlike the [`clusterdrill`](https://github.com/onahFran6/clusterdrill)
practice-bank repository, there is no GPL-licensed content here.
