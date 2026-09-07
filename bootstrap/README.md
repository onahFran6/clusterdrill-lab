# bootstrap/

Cloud-agnostic Kubernetes bootstrap: kubeadm, containerd, Cilium, and the
`clusterdrill` package. Written fresh against public kubeadm and Cilium
documentation - no code or text from any private or course-provided
script. Consumes only the [common output contract](../providers/README.md#the-common-output-contract)
any `providers/<cloud>/` module produces; nothing here is AWS-specific
(verify with `grep -ri aws .` from this directory - it should be clean).
See [`../docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md) for a diagrammed view of
how this flow fits into the whole system.

This doc covers how to *run* this bootstrap. For a narrative explanation
of what each script does and why, detailed enough to reproduce the
cluster by hand without running any of these scripts, see
[`../docs/BOOTSTRAP-DEEPDIVE.md`](../docs/BOOTSTRAP-DEEPDIVE.md).

## Flow

1. A `providers/<cloud>/` module provisions the nodes (`terraform apply`).
2. `run.sh` reads that module's Terraform outputs and, over SSH:
   - Runs [`node-common.sh`](node-common.sh) on every node (disables
     swap, installs containerd, kubelet, kubeadm, kubectl). The
     containerd/kube-package install steps dispatch on OS family
     ([`lib/os-family.sh`](lib/os-family.sh) detects Debian- vs
     RHEL-family from `/etc/os-release`, then sources
     [`lib/debian.sh`](lib/debian.sh) or [`lib/rhel.sh`](lib/rhel.sh)) -
     see "Known limitations" below for how verified each path is.
   - Runs [`control-plane.sh`](control-plane.sh) on the control-plane
     node (`kubeadm init`, installs Cilium, generates the worker join
     command).
   - Runs [`worker.sh`](worker.sh) on every worker node (`kubeadm join`,
     using the command `control-plane.sh` generated).
   - Only once every worker has joined, runs
     [`deploy-appliance.sh`](deploy-appliance.sh) on the control-plane
     node to install and deploy `clusterdrill` - its Deployment has no
     toleration for the control-plane's own taint, so it can only
     schedule once a worker actually exists to run it (this is also why
     it's a separate script from `control-plane.sh`, not the tail end of
     it: deploying it any earlier just hangs until `kubectl rollout
     status`'s own timeout in any real, non-single-node lab).
   - Then runs [`deploy-headlamp.sh`](deploy-headlamp.sh) on the
     control-plane node to install the
     [Headlamp](https://github.com/kubernetes-sigs/headlamp) dashboard
     (`../dashboard/headlamp-manifest.yaml`) - same ordering constraint
     and same reason as the appliance above.

```sh
terraform -chdir=../providers/aws output -json > outputs.json
./run.sh outputs.json ~/.ssh/id_ed25519
```

`../compatibility.json` is the machine-readable contract between this lab,
the `clusterdrill` application release it installs, and the Headlamp
dashboard it also deploys - supported Kubernetes range, exact
versions/image references, install methods, required privileges, and the
smoke-test commands `deploy-appliance.sh`/`deploy-headlamp.sh` themselves
run. `check_compatibility_contract.sh` verifies it stays in sync with the
actual pinned values in `node-common.sh`/`deploy-appliance.sh`/
`dashboard/headlamp-manifest.yaml` - CI runs it on every change to any of
them.

### Installing while the app repository is still private

No `clusterdrill` package is published to PyPI - `deploy-appliance.sh`
installs a wheel from the app repository's own GitHub Release instead
(see `compatibility.json`'s `app.install_method`). That works with a
plain public URL once the app repository is public; until then, pass a
GitHub token (one that can read that repository) as `run.sh`'s third
argument - a **file path**, never the token value itself, the same
convention `run.sh` already uses for the SSH private key:

```sh
./run.sh outputs.json ~/.ssh/id_ed25519 ~/.clusterdrill-github-token
```

The token file is copied to the control-plane node, used once, and
deleted immediately after - it's never logged, never becomes a
command-line argument on either end of the SSH connection, and this
repository never sees its contents.

## Known limitations

- **The deployed image may be stale.** `deploy-appliance.sh` resolves
  the image the same way the Minikube path's `clusterdrill local
  install` does without `--image`: the release digest paired with the
  installed package version. Until a release matching current source is
  published, this is a real, honest limitation - see the practice-bank
  README's "Release policy" section for the full explanation of why an
  older published image doesn't reflect current source.
- **Single control-plane, not HA.** This is a disposable practice lab,
  not a production reference architecture - one control-plane node is
  the deliberate scope.
- **The RHEL-family OS path (`lib/rhel.sh`) has been verified once,
  manually, against a real Rocky Linux 9 target - it is not yet in
  CI.** `providers/aws/` only ever provisions Ubuntu, so this was a
  privileged, systemd-enabled Rocky 9 container, not `providers/aws/`
  itself: `os_install_containerd`, `os_install_kube_packages`, and
  `os_install_appliance_python_deps` all ran for real, and `kubeadm
  init` produced a fully healthy control plane (etcd, kube-apiserver,
  kube-controller-manager, and kube-scheduler all `Running`). That run
  caught and fixed a real bug: dnf's `exclude=` line blocks the
  packages it names from a plain `dnf install`, not just a later `dnf
  upgrade` (unlike `apt-mark hold`) - `os_install_kube_packages` now
  adds it to the repo file only after the install, not in the same
  write. Fedora's "default `python3` may already be >= 3.11" branch
  (see `os_install_appliance_python_deps`) was separately spot-checked
  on a real Fedora 41 container and confirmed correct. Two failures
  during that same run were nested-container-testing artifacts, not
  code bugs, and needed no code change: `swapoff -a` can't disable the
  *host* Docker Desktop VM's own swap from inside a container, and
  containerd's overlay snapshotter can't stack on the host's own
  overlay2 root filesystem ("overlay-on-overlay") - both are non-issues
  on a real target VM. This still isn't wired into CI (see the
  `run.sh`/`/tmp/lib` bullet below, and `providers/aws`'s Ubuntu-only
  scope) - same honesty bar as the Debian/Ubuntu path's own
  real-AWS-run note above, just for a manual RHEL-family run instead of
  a CI one.
- **`run.sh` ships `bootstrap/lib/` to each remote host at a hardcoded
  path (`/tmp/lib`), coupled to `run_remote_script`'s own hardcoded
  flatten target (`/tmp/<script-name>`).** Nothing enforces this
  structurally - if either path ever changes without the other, a real
  SSH-driven run breaks with a `source: file not found` on the next run,
  silently, since CI's own e2e job never calls `run.sh` at all (it runs
  the scripts directly from a full repo checkout, where this coupling
  doesn't exist). See the cross-referencing comments at `run.sh`'s
  `scp -r ... /tmp/lib` line and `node-common.sh`/`deploy-appliance.sh`'s
  `source` line.
- **The kubeadm/Cilium/clusterdrill bootstrap flow is verified in CI on a
  real single-node kubeadm cluster** (`.github/workflows/lab-quality-gate.yml`'s
  `app-lab-compatibility-e2e` job - node-common.sh, control-plane.sh, and
  deploy-appliance.sh run for real on the CI runner itself, install the
  exact published release, and the deployed appliance's own smoke test
  must pass) **and has been run end to end against a real
  AWS-provisioned multi-node cluster**, including a mixed
  amd64-control-plane/arm64-worker lab: `terraform apply` against
  `../providers/aws/`, both nodes joined, the appliance scheduled onto
  the (arm64) worker and passed its own health check, and it was reached
  over its NodePort from outside AWS entirely. That first real run is
  also what found and fixed several bugs CI's single-node shape can't
  catch: the ordering issue this file's own "Flow" section above now
  documents (deploying the appliance before any worker joins would hang
  until `kubectl rollout status`'s own timeout), the security-group
  description AWS's API rejects, `run.sh` never exposing
  `deploy-appliance.sh`'s repo override, and Ubuntu 22.04's apt-shipped
  pipx predating the `pipx environment` subcommand this script relies
  on.

## Security notes

- `run.sh` uses `StrictHostKeyChecking=accept-new`, not `no` - it trusts
  a host key on first connection (normal for a freshly-provisioned,
  never-before-seen instance) but still detects and refuses a *changed*
  key on a later connection.
- No script here ever reads, logs, or transmits your SSH private key
  contents - `run.sh` only ever passes `-i <path>` to `ssh`/`scp`,
  which read the file locally themselves.
- `deploy-appliance.sh` generates a random login password for the
  appliance and prints it once at the end of the run - it is not
  written to any file this script controls beyond the in-cluster
  Secret `local_install` itself already creates.
- A GitHub token, when supplied for the still-private-app-repository
  fetch above, is only ever a file path passed between `run.sh` and
  `deploy-appliance.sh` - never a command-line argument or logged value
  on either end of the SSH connection - and `deploy-appliance.sh`
  deletes the remote copy of that file immediately after using it, on
  every exit path (a `trap`, not just the success path).
