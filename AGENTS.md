# ClusterDrill Lab

A disposable, provider-pluggable Kubernetes lab: Terraform provisions the VMs, a cloud-agnostic
bootstrap installs Kubernetes (kubeadm, containerd, Cilium) and the `clusterdrill` practice-bank
appliance on top. Written clean-room against public documentation - no code, text, or
account-specific configuration copied from any private or course-provided source. See `README.md`
for quick start and `docs/ARCHITECTURE.md` / `docs/BOOTSTRAP-DEEPDIVE.md` for the full system
design.

This is a public repo (`onahFran6/clusterdrill-lab`), extracted from a private monorepo
(`kcad-aws-workspace`). Treat it as standalone: don't assume access to that monorepo's docs,
history, or internal automation (bb-factory, agent-trunk, etc.) - none of that applies here.

## Structure

- `providers/aws/` - AWS Terraform root module (built): `main.tf`, `variables.tf`, `outputs.tf`.
  Produces the [common output contract](providers/README.md#the-common-output-contract) that
  `bootstrap/` consumes. `providers/gcp/` is a reserved seam, not built.
- `bootstrap/` - cloud-agnostic shell scripts, run in this order by `run.sh` over SSH:
  `node-common.sh` (every node) -> `control-plane.sh` (kubeadm init, Cilium, join command) ->
  `worker.sh` (every worker, kubeadm join) -> `deploy-appliance.sh` (clusterdrill, once a worker
  exists) -> `deploy-headlamp.sh` (dashboard). See `bootstrap/README.md` for why that ordering is
  load-bearing.
- `dashboard/` - the Headlamp manifest `deploy-headlamp.sh` applies.
- `compatibility.json` - the machine-readable contract between this lab, the `clusterdrill`
  release it installs, and the Headlamp dashboard version.
- `docs/` - whole-system documentation that doesn't belong next to any single directory's code:
  `ARCHITECTURE.md` (system-wide diagrammed overview) and `BOOTSTRAP-DEEPDIVE.md` (narrative,
  reproduce-by-hand walkthrough of the bootstrap flow). See `docs/README.md` for the full reading
  order, including the directory-local docs (`bootstrap/README.md`, `providers/README.md`, etc.)
  that stay next to their code instead of moving here.

## The one hard rule

Nothing under `bootstrap/` may depend on a specific cloud's metadata service, CLI, or SDK. A
provider root module hands `bootstrap/` everything it needs (IP, instance ID) as a plain argument
or Terraform output - a bootstrap script must never reach out and detect cloud-specific context
itself. If unsure whether something counts as cloud-specific, ask rather than guess (see
`CONTRIBUTING.md`).

## Terraform conventions

- Run `terraform fmt` and `terraform validate` (from the changed root module) before committing.
- Every variable needs a `description`; add a `validation` block where a bad value would fail
  confusingly late.
- Commit `.terraform.lock.hcl` when provider requirements change.
- Update `terraform.tfvars.example` when variables change.
- Never commit `terraform.tfvars`, `*.tfstate`, `*.tfplan`, or anything under `.terraform/`.

## Documentation

Docs are not a one-time artifact - keep them in sync with the system they describe.

- If a change alters system-wide behavior (the top-level flow, the seam between `providers/` and
  `bootstrap/`, a new component, a changed diagram-worthy relationship), update `docs/ARCHITECTURE.md`
  in the same PR.
- If a change alters what a bootstrap script does or why (a new step, a changed flag, a different
  ordering constraint), update `docs/BOOTSTRAP-DEEPDIVE.md` in the same PR.
- If a change adds a genuinely new area of whole-system knowledge that doesn't fit either existing
  doc or any directory-local README, add a new file under `docs/` rather than stretching an existing
  doc to cover an unrelated topic - then link it from `docs/README.md`.
- Directory-local how-to-run docs (`bootstrap/README.md`, `providers/README.md`,
  `providers/aws/README.md`) stay next to the code they describe, not in `docs/` - `docs/` is for
  whole-system explanation, not per-directory usage instructions.
- A PR that changes behavior without a matching doc update should call that out explicitly (and
  why it's safe to skip), not leave it unmentioned.

## Verification before opening a PR

- `terraform fmt -check` and `terraform validate` (from `providers/aws/`, or the relevant root
  module)
- `shellcheck bootstrap/*.sh` if `bootstrap/` changed
- No real cloud credentials, account IDs, or state files in the diff

Fill out `.github/PULL_REQUEST_TEMPLATE.md` for real - don't skip checklist items.

## Commit message convention

This repo's `release-please` automation ([`MAINTAINING.md`](MAINTAINING.md)) parses commit history
to generate the CHANGELOG and decide the next version - use
[Conventional Commits](https://www.conventionalcommits.org/) prefixes (`fix:`, `feat:`, `chore:`,
`docs:`, `test:`, `ci:`, `refactor:`). A commit release-please can't parse is silently dropped from
both the changelog and version bump. Never manually edit `CHANGELOG.md` - it's auto-generated.

Use the `good-commits` skill (`~/.claude/skills/good-commits/`) when committing or opening a PR for
atomic-commit splitting, message quality, and PR description structure, layered on top of the
Conventional Commits prefix requirement above.

**Commit mode: confirm** - show the proposed commit split and message(s), and the drafted PR
description, before running `git commit` / `gh pr create`, on every branch, no exceptions.
