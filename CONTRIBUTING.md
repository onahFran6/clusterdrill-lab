# Contributing to ClusterDrill Lab

Thanks for considering a contribution. This document covers how the
Terraform root modules and bootstrap scripts are structured, and how to
verify your work locally before opening a PR.

By contributing, you agree to license your changes under this project's
[MIT license](LICENSE), and you confirm the content is your own work.

## Structure

- `providers/aws/` - the AWS Terraform root module. `providers/gcp/` is a
  reserved, not-yet-built seam for a future provider.
- `bootstrap/` - cloud-agnostic shell scripts that install Kubernetes
  (kubeadm, containerd, Cilium) and the `clusterdrill` appliance on top of
  whatever VMs a provider module created.

## The one hard rule: `bootstrap/` stays cloud-agnostic

Nothing under `bootstrap/` may depend on a specific cloud's metadata
service, CLI, or SDK. A provider root module's job is to hand `bootstrap/`
everything it needs (an IP address, an instance ID) as a plain argument or
Terraform output - never have a bootstrap script reach out and detect
cloud-specific context itself. This is easy to violate without realizing
it: even something that looks generic, like querying the link-local
metadata IP `169.254.169.254`, uses a different response schema on AWS,
GCP, and Azure. If you're not sure whether something you're adding counts
as cloud-specific, ask in the PR rather than guess.

## Terraform conventions

- Run `terraform fmt` before committing; CI runs `terraform fmt -check`
  and will fail on unformatted code.
- Run `terraform validate` in the root module you changed.
- Every variable needs a `description`. Add a `validation` block for
  anything where a bad value would fail confusingly late (during `apply`,
  or worse, after real cloud resources exist) rather than at plan time.
- Commit `.terraform.lock.hcl` for any root module whose provider
  requirements changed. This repository's `.gitignore` deliberately
  negates the usual "don't commit generated Terraform files" pattern for
  this one file - see the comment there before touching it.
- Update `terraform.tfvars.example` when you add, remove, or rename a
  variable.
- Never commit `terraform.tfvars`, `*.tfstate`, `*.tfplan`, or anything
  under a `.terraform/` directory - these hold real (or potentially real)
  account-specific and secret values.

## Security scanning

CI runs a static Terraform misconfiguration scan (Trivy's config scanner)
against every root module on every PR that touches `providers/**`. It
runs without any real cloud credentials - it never applies anything, only
reads the Terraform source. If a finding is a deliberate, documented
tradeoff rather than a real issue (for example, the security group being
intentionally scoped by an operator-supplied CIDR rather than a fixed
range), say so in the PR rather than suppressing the finding silently.

## Issue labels

| Label | Applied by | Meaning |
| --- | --- | --- |
| `bug` | Bug report issue form | Something is broken or incorrect. |

General questions and discussion don't get a label - they go to
[Discussions](../../discussions) instead of an issue (see
[`SUPPORT.md`](SUPPORT.md)). Security reports never become a public
issue at all (see [`SECURITY.md`](SECURITY.md)), so there's no public
`security` label either.

## Governance, support, and security

- [`GOVERNANCE.md`](GOVERNANCE.md) - how decisions get made.
- [`SUPPORT.md`](SUPPORT.md) - where to ask a question vs. file an issue.
- [`SECURITY.md`](SECURITY.md) - how to report a vulnerability privately.

## Code of conduct

Participation in this project is governed by [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md)
(Contributor Covenant).
