# ClusterDrill Lab

[![Lab quality gate](https://github.com/onahFran6/clusterdrill-lab/actions/workflows/lab-quality-gate.yml/badge.svg)](https://github.com/onahFran6/clusterdrill-lab/actions/workflows/lab-quality-gate.yml)
[![Latest release](https://img.shields.io/github/v/release/onahFran6/clusterdrill-lab)](https://github.com/onahFran6/clusterdrill-lab/releases)
[![License: MIT](https://img.shields.io/github/license/onahFran6/clusterdrill-lab)](LICENSE)

A disposable, provider-pluggable Kubernetes lab that provisions a cluster and installs a released
[`clusterdrill`](https://github.com/onahFran6/clusterdrill) appliance.

## Contents

- [Overview](#overview)
- [Supported providers](#supported-providers)
- [The `clusterdrill` practice bank](#the-clusterdrill-practice-bank)
- [Structure](#structure)
- [Quick start](#quick-start)
- [Dashboard](#dashboard)
- [Operating this lab](#operating-this-lab)
- [Roadmap and non-goals](#roadmap-and-non-goals)
- [More documentation](#more-documentation)
- [Licensing](#licensing)

## Overview

Terraform provisions the VMs. A cloud-agnostic bootstrap then installs Kubernetes (kubeadm,
containerd, Cilium) and, opt-in, the `clusterdrill` CKAD practice-bank appliance on top - see
[Quick start](#quick-start). Every root module under `providers/` hands the bootstrap the same four
values, so swapping clouds never touches `bootstrap/`'s own code. Written clean-room against public
documentation only - no code or text from any private or course-provided source.

## Supported providers

| Provider | Status | Docs |
| --- | --- | --- |
| AWS | Built and tested | [`providers/aws/README.md`](providers/aws/README.md) |
| GCP | Not built - a reserved seam | [`providers/gcp/README.md`](providers/gcp/README.md) |

The Quick start below is AWS-only for that reason: it's the only provider with a working Terraform
root module today.

## The `clusterdrill` practice bank

This lab exists to run [`clusterdrill`](https://github.com/onahFran6/clusterdrill): the CKAD
question set, grading CLI, appliance image, and Helm chart. This repository only provisions the
infrastructure and, if you opt in, installs a pinned release on top (see
[`compatibility.json`](compatibility.json) for the exact version). The question set and grading
logic live in the `clusterdrill` repository itself, along with a Minikube-based local-install path
for running it without a cloud lab at all.

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

[`providers/README.md`](providers/README.md) documents the output contract between the two
layers, and [`docs/README.md`](docs/README.md) is the full reading order for every doc in this
repository.

## Quick start

**Prerequisites** - full detail in [`providers/aws/README.md#prerequisites`](providers/aws/README.md#prerequisites):

- AWS credentials Terraform can use: `aws configure`, or export `AWS_ACCESS_KEY_ID` /
  `AWS_SECRET_ACCESS_KEY` (add `AWS_SESSION_TOKEN` for temporary/SSO credentials). Without one of
  these, `terraform plan` fails with `No valid credential sources found`.
- An SSH key pair. Don't have one? `ssh-keygen -t ed25519 -C "you@example.com"`.
- Terraform >= 1.5.0.

Clone a tagged release, not `main` - see [Releases](https://github.com/onahFran6/clusterdrill-lab/releases)
for the latest tag:

```sh
git clone --branch clusterdrill-lab-v0.1.0 --depth 1 \
  https://github.com/onahFran6/clusterdrill-lab.git
cd clusterdrill-lab/providers/aws
cp terraform.tfvars.example terraform.tfvars
```

Set the two variables `terraform.tfvars` has no default for:

| Variable | How to get it |
| --- | --- |
| `ssh_public_key` | `cat ~/.ssh/id_ed25519.pub` |
| `allowed_ssh_cidr` | `curl -s https://checkip.amazonaws.com`, then append `/32`. Can't be `0.0.0.0/0`. |

Everything else already has a tested default - see the
[configuration reference](providers/aws/README.md#configuration-reference) to change region,
instance size, or architecture.

```sh
terraform init
terraform plan     # review what it's about to create before anything is billed
terraform apply

terraform output -json > ../../bootstrap/outputs.json
cd ../../bootstrap
./run.sh outputs.json ~/.ssh/id_ed25519   # private key paired with ssh_public_key above
```

This gives you a bare, working Kubernetes cluster with no `clusterdrill` footprint at all - just
Kubernetes, Cilium, and the Headlamp dashboard. **Set `CLUSTERDRILL_DEPLOY=1` to also have the
`clusterdrill` appliance installed into the cluster:**

```sh
CLUSTERDRILL_DEPLOY=1 ./run.sh outputs.json ~/.ssh/id_ed25519
```

`run.sh` prints a login password near the end when `CLUSTERDRILL_DEPLOY=1` - see
[Verifying the lab](providers/aws/README.md#verifying-the-lab) for the appliance URL and next
steps. Bring just the appliance back down later, independent of the rest of the lab, with
`helm uninstall clusterdrill --namespace clusterdrill-system` on the control-plane node.

## Dashboard

Every lab includes a [Headlamp](https://github.com/kubernetes-sigs/headlamp) web dashboard,
deployed automatically as part of the standard bootstrap. It's RBAC-aware and read-only, including
Secrets - reasonable for this single-operator lab, since the operator already has unrestricted
`kubectl` access over SSH. See [`providers/aws/README.md#headlamp-dashboard`](providers/aws/README.md#headlamp-dashboard)
for how to reach it and log in.

## Operating this lab

You own the cloud account, credentials, SSH key pair, and Terraform state. This project holds none
of these on your behalf and generates no credentials for you.

### Cost

This provisions real, billed cloud resources with no automated cost control, budget alert, or
auto-shutdown. Destroy the lab when you're done - see [`providers/aws/README.md#cost`](providers/aws/README.md#cost).

### Lifecycle

Provision it, use it, destroy it - this is a disposable practice lab, not a persistent environment.
See [`providers/aws/README.md#recovery`](providers/aws/README.md#recovery) for node failures and
state loss, and [Not for production use](providers/aws/README.md#not-for-production-use) for the
full disclaimer.

## Roadmap and non-goals

- **GCP support** - a reserved seam, not yet built; see [`providers/gcp/README.md`](providers/gcp/README.md)
  for exactly what a future root module would need to produce.
- **Cost automation** (budget alerts, auto-shutdown) - an operator's cost tooling is tied to their
  own account and billing setup in ways that don't generalize as a portable feature.
- **High availability** - a single control-plane node is the intended scope for a disposable
  practice lab, not a gap to fill.
- **Backup/snapshot automation** - re-provisioning from scratch is the intended recovery path; see
  [`providers/aws/README.md#backup`](providers/aws/README.md#backup).

## More documentation

| Doc | Covers |
| --- | --- |
| [`docs/README.md`](docs/README.md) | Full reading order for every doc in this repository |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Diagrammed, whole-system overview |
| [`docs/BOOTSTRAP-DEEPDIVE.md`](docs/BOOTSTRAP-DEEPDIVE.md) | How and why the bootstrap builds the cluster, detailed enough to reproduce by hand |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Terraform/bootstrap conventions and local verification before a PR |
| [`MAINTAINING.md`](MAINTAINING.md) | Versioning policy and the release-please runbook |
| [`GOVERNANCE.md`](GOVERNANCE.md) | How decisions get made |
| [`SUPPORT.md`](SUPPORT.md) | Where to ask a question vs. file a bug |
| [`SECURITY.md`](SECURITY.md) | How to report a vulnerability privately |
| [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) | Contributor Covenant |

## Licensing

MIT - see [`LICENSE`](LICENSE). The [`clusterdrill`](https://github.com/onahFran6/clusterdrill)
practice-bank repository includes GPL-licensed content; this repository does not.
