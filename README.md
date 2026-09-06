# ClusterDrill Lab

A disposable, provider-pluggable Kubernetes lab: Terraform provisions
the VMs, a cloud-agnostic bootstrap installs Kubernetes (kubeadm,
containerd, and Cilium) and the `clusterdrill` practice-bank appliance
on top. Written clean-room against public documentation - no code,
text, or account-specific configuration copied from any private or
course-provided source.

## Structure

```text
clusterdrill-lab/
  providers/
    aws/        Terraform root module - provisions the VMs (built first)
    gcp/        reserved seam, not built
  bootstrap/    cloud-agnostic: kubeadm, containerd, Cilium, clusterdrill
  dashboard/    Headlamp web dashboard, deployed by bootstrap alongside clusterdrill
  LICENSE       MIT
```

See [`providers/README.md`](providers/README.md) for the output contract
that connects the two, and [`bootstrap/README.md`](bootstrap/README.md)
for the bootstrap flow itself.

## Quick start (AWS)

```sh
cd providers/aws
cp terraform.tfvars.example terraform.tfvars   # fill in your SSH key and IP
terraform init
terraform apply

terraform output -json > ../../bootstrap/outputs.json
cd ../../bootstrap
./run.sh outputs.json ~/.ssh/id_ed25519
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
Unlike the practice-bank repository, there is no GPL-licensed content
here.
