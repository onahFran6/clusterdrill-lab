# Security policy

## Reporting a vulnerability

Please report security vulnerabilities privately, not as a public GitHub
issue - use
[GitHub's private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing/privately-reporting-a-security-vulnerability)
feature on this repository (the "Report a vulnerability" button under the
Security tab). This opens a private draft security advisory visible only to
you and the maintainers, so the issue isn't disclosed before a fix is
available.

Include, if you can:

- What kind of vulnerability it is (e.g. an over-broad security group rule,
  a Terraform misconfiguration, an insecure default in a bootstrap script).
- The affected file(s) or component (`providers/aws/`, `providers/gcp/`,
  `bootstrap/`).
- Steps to reproduce, or a minimal proof of concept.
- The Terraform and provider version you tested against.

## Response expectations

This is a single-maintainer project maintained outside of paid working
hours - please expect an initial acknowledgement within 5 business days,
not immediate response. A fix or mitigation timeline will be communicated
once the report is triaged; there's no fixed SLA, but valid reports are
prioritized over other work.

## Scope

In scope: the Terraform root modules under `providers/`, and the bootstrap
scripts under `bootstrap/`.

Out of scope: vulnerabilities in third-party dependencies themselves (the
`hashicorp/aws` provider, Cilium, containerd, kubeadm) - report those
upstream; and any cost, availability, or configuration decision an operator
makes in their own `terraform.tfvars` (a deliberately permissive
`allowed_ssh_cidr` an operator sets for themselves is their own choice, not
a vulnerability in this project).

## Supported versions

`clusterdrill-lab` follows [semantic versioning](https://semver.org/),
distinct from the `clusterdrill` application's own version - see
[`MAINTAINING.md`](MAINTAINING.md) for the full policy. Pre-1.0 (the
current `0.x` line), there is still only one supported line: the latest
tagged release and the latest revision on the default branch both
receive fixes, not a matrix of parallel maintained minor versions. If a
vulnerability affects an older tagged release, the fix lands as a new
release on the current line rather than a backport to the older tag.
This will be revisited once there's a 1.0 release and, if demand
warrants it, more than one maintained line at a time.
