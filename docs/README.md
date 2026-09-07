# Documentation

This folder holds whole-system documentation: docs that explain the project as a whole, rather
than how to use one specific directory's code. If you're new to this repository, read the docs
below in this order before you start changing anything.

## Reading order

1. [`../README.md`](../README.md) - what this project is, quick start, and the top-level
   structure. Start here if you haven't already.
2. [`ARCHITECTURE.md`](ARCHITECTURE.md) - a diagrammed, system-wide overview: what provisions the
   VMs, what installs Kubernetes, what installs the CNI, and what installs the practice-bank app,
   in that order, without requiring you to read any `.tf` or `.sh` file first. Read this before
   touching either `providers/` or `bootstrap/`.
3. [`BOOTSTRAP-DEEPDIVE.md`](BOOTSTRAP-DEEPDIVE.md) - a narrative, step-by-step walkthrough of
   *how* and *why* `bootstrap/` builds the cluster the way it does, detailed enough to reproduce
   the same control-plane/worker/CNI setup by hand. Read this before changing anything under
   `bootstrap/`.
4. [`../CONTRIBUTING.md`](../CONTRIBUTING.md) - the one hard rule (`bootstrap/` stays
   cloud-agnostic), Terraform conventions, commit message convention, and how to verify your work
   before opening a PR.

## Directory-local docs (not in this folder)

Docs that explain how to *run* something stay next to the code they describe, instead of moving
here:

- [`../providers/README.md`](../providers/README.md) - the output contract between a provider
  module and `bootstrap/`.
- [`../providers/aws/README.md`](../providers/aws/README.md) - AWS-specific setup, cost, and the
  full lifecycle runbook (destroy, recovery, patch/upgrade, compatibility matrix).
- [`../bootstrap/README.md`](../bootstrap/README.md) - how to invoke `run.sh`, its arguments, and
  known limitations.

## Other project docs

- [`../MAINTAINING.md`](../MAINTAINING.md) - versioning policy and the release process.
- [`../GOVERNANCE.md`](../GOVERNANCE.md) - how decisions get made.
- [`../SUPPORT.md`](../SUPPORT.md) - where to ask a question vs. file an issue.
- [`../SECURITY.md`](../SECURITY.md) - how to report a vulnerability privately.

## Keeping this folder current

`ARCHITECTURE.md` and `BOOTSTRAP-DEEPDIVE.md` are living docs, not one-time write-ups - see
[`../AGENTS.md`](../AGENTS.md#documentation) for the rule on updating them (or adding a new file
here) whenever a change alters system-wide behavior.
