# Maintaining ClusterDrill Lab

This document is for whoever is bumping a pinned dependency, cutting a
release, or otherwise doing maintainer-shaped work on `clusterdrill-lab`
- not for a first-time contributor sending a normal PR (see
[`CONTRIBUTING.md`](CONTRIBUTING.md) for that).

## Versioning

`clusterdrill-lab` has its own [semantic versioning](https://semver.org/)
line, separate from the `clusterdrill` application's own version (the
`app.version` field in [`compatibility.json`](compatibility.json)). A
lab release is a snapshot of this repository - the Terraform root
modules under `providers/`, the bootstrap scripts, and the
`compatibility.json` contract they were tested against together - not a
snapshot of the application itself.

- Releases are tagged `clusterdrill-lab-v<major>.<minor>.<patch>` (for
  example `clusterdrill-lab-v0.1.0`), never a bare `v<version>` - this
  repository's git history also carries the application's own `v0.1.0`
  tag from before the two were split into separate release lines, and an
  unprefixed tag here would collide with that name in tooling and in a
  human's head.
- Pre-1.0 (the whole `0.x` line): a breaking change bumps the minor
  version, everything else bumps the patch version. Nothing here is
  guaranteed API/interface-stable pre-1.0 - see
  [`SECURITY.md`](SECURITY.md)'s "Supported versions" section for what
  that means for security fixes.
- What counts as a breaking change for a Terraform root module: a
  variable rename or removal, a changed variable's meaning or default
  that would alter previously-applied infrastructure, or a change to
  [`providers/README.md`](providers/README.md)'s output contract. A new
  optional variable with a backward-compatible default is not breaking.
- 1.0.0 will be cut deliberately by a maintainer (`--release-as` override
  in release-please, not an automatic bump) once the interface is judged
  stable enough to promise - there's no fixed date or criteria for that
  yet.

## Releases are automated by release-please

[`release-please`](https://github.com/googleapis/release-please) reads
[Conventional Commits](https://www.conventionalcommits.org/) on this
repository's `main` branch and maintains a standing "release PR" that
accumulates a `CHANGELOG.md` entry and the next version number. See
[`.github/workflows/release-please.yml`](.github/workflows/release-please.yml),
[`release-please-config.json`](release-please-config.json), and
[`.release-please-manifest.json`](.release-please-manifest.json).

**This means every commit merged to `main` needs a
Conventional Commits prefix** (`fix:`, `feat:`, `chore:`, `docs:`, etc.,
optionally with a `!` or a `BREAKING CHANGE:` footer for a breaking
change) for release-please to include it correctly - a commit release-please
can't parse is silently omitted from the changelog and doesn't influence
the version bump. This is a change from this branch's own pre-existing
commit style (compare `git log` before this policy existed) - going
forward, conventional-commit prefixes are required, not optional.

**CHANGELOG.md is auto-generated.** Don't hand-edit it (matching the
`clusterdrill` application's own approach, `docs/open-source/PLAN.md`
§4.4) - a manual edit will be overwritten or produce a conflicting diff
the next time release-please updates its PR.

**To cut a release:**

1. Merge the standing release-please PR (titled something like
   `chore(clusterdrill-lab): release clusterdrill-lab x.y.z`) once you've
   reviewed its generated `CHANGELOG.md` diff and are satisfied it
   reflects what should ship.
2. release-please tags the merge commit and publishes a GitHub Release
   automatically - no separate manual tagging step.
3. There is no separate publish/build step today (unlike the
   `clusterdrill` app's own tag -> PyPI/Docker publish workflow) - a lab
   release is the tag, the GitHub Release, and the CHANGELOG entry, since
   there's no package registry a Terraform root module or shell script
   gets published to.

**One-time bootstrap note:** `release-please-config.json` currently pins
`"release-as": "0.1.0"` on the `.` package. This is deliberate for the
very first release only - it forces release-please's first standing PR
to cut `clusterdrill-lab-v0.1.0` (matching this project's existing
`compatibility.json` snapshot) instead of the `1.0.0` release-please
would otherwise default to for a repository with no prior release tag at
all (`bump-minor-pre-major`/`bump-patch-for-minor-pre-major` only affect
the bump *after* a baseline release exists, not the very first one).
**Remove the `release-as` line from `release-please-config.json` once
`clusterdrill-lab-v0.1.0` is tagged** - leaving it in place would pin
every subsequent release to `0.1.0` forever instead of letting
Conventional Commits drive the version forward normally.

## Version-bump runbook

This is the full checklist for bumping any pinned dependency - a
Kubernetes minor, Cilium, Ubuntu LTS release, or the `hashicorp/aws`
provider constraint. Every piece here was previously tribal knowledge
scattered across `compatibility.json`'s own `$comment`,
`bootstrap/check_compatibility_contract.sh`, and
`providers/aws/README.md`'s Patch/upgrade section - this is the one place
that connects them end-to-end.

1. **Update the actual pin.** Depending on what's changing:
   - Kubernetes minor: `KUBERNETES_MINOR` in
     [`bootstrap/node-common.sh`](bootstrap/node-common.sh).
   - Cilium version: `CILIUM_VERSION` in
     [`bootstrap/control-plane.sh`](bootstrap/control-plane.sh) (and
     `CILIUM_CLI_VERSION` alongside it if the CLI needs bumping too).
   - Ubuntu release: the AMI filter pattern in
     [`providers/aws/main.tf`](providers/aws/main.tf).
   - `hashicorp/aws` provider: the version constraint in
     [`providers/aws/versions.tf`](providers/aws/versions.tf), then run
     `terraform init -upgrade` in `providers/aws/` and commit the
     resulting `.terraform.lock.hcl` diff (Dependabot proposes this pin
     bump automatically - see below - but the lock file update is the
     same either way).
2. **Update `compatibility.json`.** Its own `$comment` field says this
   explicitly: this file and the pins above must change together in the
   same commit, never drift apart. Run
   `bash bootstrap/check_compatibility_contract.sh` locally to confirm
   before committing - it's the same check CI runs.
3. **Update `providers/aws/README.md`'s Compatibility matrix table** (the
   `## Compatibility matrix` section) so the documented versions match
   what's now actually pinned.
4. **Re-run the E2E job.** Push a PR and let
   `.github/workflows/lab-quality-gate.yml`'s
   `app-lab-compatibility-e2e` job run - it bootstraps a real
   single-node cluster on the runner itself and proves the new pins
   actually work together, not just that the files are internally
   consistent.
5. **Merge, then let release-please handle the CHANGELOG and version
   bump** - write the merged commit(s) as `fix:`/`feat:` per the
   Conventional Commits rule above so release-please picks them up; you
   don't hand-write a CHANGELOG entry.
6. **Merge the resulting release-please PR** to tag the release (see
   "Releases are automated by release-please" above).

## Dependency-drift automation

Dependabot ([`.github/dependabot.yml`](.github/dependabot.yml)) opens a
PR automatically for:

- GitHub Actions used in this branch's own workflows (SHA-pinned `uses:`
  lines - Dependabot understands SHA pins and proposes the new SHA with a
  human-readable version in the PR description).
- The `hashicorp/aws` provider constraint and lock file in
  `providers/aws/`.

A Dependabot PR for either still needs the version-bump runbook above
(specifically the `compatibility.json` and README-matrix steps) before
merging - accepting the PR as-is only updates the pin/lock file itself.

**Not automated: a scheduled live-AWS drift-detection job.** The issue
that established this policy (`#168`) also scoped a periodic (e.g.
monthly) CI job that would run a real `terraform plan` (or full
apply/destroy cycle) against a live AWS account to catch drift - an AMI
filter silently no longer matching, AWS deprecating an instance type -
before a user's own `terraform apply` does. That job needs real cloud
credentials stored as a repository secret, which is a cost and
credential-custody decision distinct from everything else in this
document (nothing else here touches a real cloud account). It is
deliberately not implemented yet, pending that decision - see the
`#168` issue thread rather than tribal knowledge if you're picking this
up later.
