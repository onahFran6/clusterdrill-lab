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
     swap, installs containerd, kubelet, kubeadm, kubectl, plus `helm`
     and `kustomize` for the operator's own CKAD practice use - see
     [`lib/practice-tools.sh`](lib/practice-tools.sh)).
     The containerd/kube-package install steps dispatch on OS family
     ([`lib/os-family.sh`](lib/os-family.sh) detects Debian- vs
     RHEL-family from `/etc/os-release`, then sources
     [`lib/debian.sh`](lib/debian.sh) or [`lib/rhel.sh`](lib/rhel.sh)) -
     see "Known limitations" below for how verified each path is.
     `helm`/`kustomize` install the same way regardless of OS family
     (a pinned-version release tarball, checksum-verified), so they
     aren't part of that per-family dispatch.
   - Runs [`control-plane.sh`](control-plane.sh) on the control-plane
     node (`kubeadm init`, installs Cilium, generates the worker join
     command).
   - Runs [`worker.sh`](worker.sh) on every worker node (`kubeadm join`,
     using the command `control-plane.sh` generated).
   - Only once every worker has joined, and only if `CLUSTERDRILL_DEPLOY=1`
     is set (see below), runs [`deploy-appliance.sh`](deploy-appliance.sh)
     on the control-plane node to `helm install`/`upgrade` the published
     `clusterdrill` chart - its Deployment has no toleration for the
     control-plane's own taint, so it can only schedule once a worker
     actually exists to run it (this is also why it's a separate script
     from `control-plane.sh`, not the tail end of it: deploying it any
     earlier just hangs until `kubectl rollout status`'s own timeout in
     any real, non-single-node lab).
   - Then runs [`deploy-headlamp.sh`](deploy-headlamp.sh) on the
     control-plane node to install the
     [Headlamp](https://github.com/kubernetes-sigs/headlamp) dashboard
     (`../dashboard/headlamp-manifest.yaml`) - same ordering constraint
     as the appliance above, but always runs regardless of
     `CLUSTERDRILL_DEPLOY`.

```sh
terraform -chdir=../providers/aws output -json > outputs.json
./run.sh outputs.json ~/.ssh/id_ed25519
```

By default this produces a bare, working Kubernetes cluster with no
`clusterdrill` footprint at all - only Headlamp is deployed alongside it.
Set `CLUSTERDRILL_DEPLOY=1` to also have the `clusterdrill` appliance
installed into the cluster:

```sh
CLUSTERDRILL_DEPLOY=1 ./run.sh outputs.json ~/.ssh/id_ed25519
```

To bring just the appliance back down later, independent of the rest of
the cluster or the Terraform-provisioned VMs themselves:

```sh
ssh -i ~/.ssh/id_ed25519 <ssh-user>@<control-plane-ip> \
  helm uninstall clusterdrill --namespace clusterdrill-system
```

### What `run.sh` prints when it finishes

A successful run's last lines are everything you need to actually use the lab - no need to go
hunting for IPs or NodePorts yourself:

```
SSH to the control plane:
  ssh -i <ssh-key> <ssh-user>@<control-plane-ip>

Headlamp dashboard: http://<control-plane-ip>:<nodeport>
  Log in with a bearer token (short-lived by design - generate one on demand):
  ssh -i <ssh-key> <ssh-user>@<control-plane-ip> kubectl create token headlamp -n headlamp-system --duration=8h
```

The Headlamp NodePort is queried fresh from the cluster right after `deploy-headlamp.sh` runs -
see `run.sh`'s own comment at that line for why (a stable fact the API server already knows, not
something worth scraping out of a remote script's stdout). The `clusterdrill` appliance itself
has no equivalent line here yet - `run.sh` doesn't print its NodePort today, only its login
password when `CLUSTERDRILL_DEPLOY=1` (from `deploy-appliance.sh`'s own output, earlier in the
same run) - see
`providers/aws/README.md`'s ["Verifying the lab"](../providers/aws/README.md#verifying-the-lab)
section for how to find and reach it in the meantime.

`../compatibility.json` is the machine-readable contract between this lab,
the `clusterdrill` application release it installs, and the Headlamp
dashboard it also deploys - supported Kubernetes range, the pinned chart
version, install methods, required privileges, and the smoke-test commands
`deploy-appliance.sh`/`deploy-headlamp.sh` themselves run.
`check_compatibility_contract.sh` verifies it stays in sync with the
actual pinned values in `node-common.sh`/`deploy-appliance.sh`/
`dashboard/headlamp-manifest.yaml` - CI runs it on every change to any of
them.

## Known limitations

- **The deployed appliance version is a deliberate pin, not always
  "latest."** `deploy-appliance.sh`'s `CLUSTERDRILL_VERSION` (kept in sync
  with `compatibility.json`'s `app.version` by
  `check_compatibility_contract.sh`) is bumped by hand, the same
  discipline as every other pinned dependency in this repo (Kubernetes
  minor, Cilium, Ubuntu release - see `MAINTAINING.md`'s version-bump
  runbook). A newer `clusterdrill` release can exist upstream before this
  repo has deliberately picked it up - that's expected, not a bug.
- **Single control-plane, not HA.** This is a disposable practice lab,
  not a production reference architecture - one control-plane node is
  the deliberate scope.
- **The RHEL-family OS path (`lib/rhel.sh`) has been verified once,
  manually, against a real Rocky Linux 9 target - it is not yet in
  CI.** `providers/aws/` only ever provisions Ubuntu, so this was a
  privileged, systemd-enabled Rocky 9 container, not `providers/aws/`
  itself: `os_install_containerd` and `os_install_kube_packages` both
  ran for real, and `kubeadm init` produced a fully healthy control
  plane (etcd, kube-apiserver, kube-controller-manager, and
  kube-scheduler all `Running`). That run caught and fixed a real bug:
  dnf's `exclude=` line blocks the packages it names from a plain `dnf
  install`, not just a later `dnf upgrade` (unlike `apt-mark hold`) -
  `os_install_kube_packages` now adds it to the repo file only after
  the install, not in the same write. Two failures during that same run
  were nested-container-testing artifacts, not code bugs, and needed no
  code change: `swapoff -a` can't disable the *host* Docker Desktop VM's
  own swap from inside a container, and containerd's overlay snapshotter
  can't stack on the host's own overlay2 root filesystem
  ("overlay-on-overlay") - both are non-issues on a real target VM. This
  still isn't wired into CI (see the `run.sh`/`/tmp/lib` bullet below,
  and `providers/aws`'s Ubuntu-only scope) - same honesty bar as the
  Debian/Ubuntu path's own real-AWS-run note above, just for a manual
  RHEL-family run instead of a CI one. (That original run also verified
  `os_install_appliance_python_deps`, since deleted alongside the rest
  of `deploy-appliance.sh`'s pipx-based install path - see git history
  before this file's move to Helm if you need that account.)
- **`run.sh` ships `bootstrap/lib/` to each remote host at a hardcoded
  path (`/tmp/lib`), coupled to `run_remote_script`'s own hardcoded
  flatten target (`/tmp/<script-name>`).** Nothing enforces this
  structurally - if either path ever changes without the other, a real
  SSH-driven run breaks with a `source: file not found` on the next run,
  silently, since CI's own e2e job never calls `run.sh` at all (it runs
  the scripts directly from a full repo checkout, where this coupling
  doesn't exist). See the cross-referencing comments at `run.sh`'s
  `scp -r ... /tmp/lib` line and `node-common.sh`'s own `source` line.
- **`lib/practice-tools.sh`'s arm64 install path (`helm`/`kustomize`) is
  implemented but not exercised by any CI job today.**
  The real e2e job below runs on an amd64 GitHub-hosted runner only;
  arm64 is only exercised by whichever architecture an operator
  actually chooses via `providers/aws/variables.tf`'s
  `control_plane_architecture`/`worker_architecture` on a real run.
  Same honesty pattern as the RHEL-family bullet above, for a
  smaller-blast-radius path.
- **The kubeadm/Cilium/clusterdrill bootstrap flow is verified in CI on a
  real single-node kubeadm cluster** (`.github/workflows/lab-quality-gate.yml`'s
  `app-lab-compatibility-e2e` job, matrixed over `CLUSTERDRILL_DEPLOY`
  both unset and `1` - node-common.sh and control-plane.sh always run for
  real on the CI runner itself; the `1` leg also runs deploy-appliance.sh,
  installs the exact pinned chart version, smoke-tests the appliance over
  its NodePort, and proves `helm uninstall` cleanly tears it back down;
  the unset leg proves a bare cluster has zero clusterdrill footprint)
  **and has been run end to end against a real AWS-provisioned multi-node
  cluster**, including a mixed amd64-control-plane/arm64-worker lab:
  `terraform apply` against `../providers/aws/`, both nodes joined, the
  appliance scheduled onto the (arm64) worker and passed its own health
  check, and it was reached over its NodePort from outside AWS entirely.
  That first real run is also what found and fixed several bugs CI's
  single-node shape can't catch: the ordering issue this file's own
  "Flow" section above now documents (deploying the appliance before any
  worker joins would hang until `kubectl rollout status`'s own timeout)
  and the security-group description AWS's API rejects.

## Security notes

- `run.sh` uses `StrictHostKeyChecking=accept-new`, not `no` - it trusts
  a host key on first connection (normal for a freshly-provisioned,
  never-before-seen instance) but still detects and refuses a *changed*
  key on a later connection.
- No script here ever reads, logs, or transmits your SSH private key
  contents - `run.sh` only ever passes `-i <path>` to `ssh`/`scp`,
  which read the file locally themselves.
- `deploy-appliance.sh` generates a random login password for the
  appliance the first time it runs and prints it once at the end - it is
  not written to any file this script controls beyond the in-cluster
  `clusterdrill-web-auth` Secret it creates. A later re-run against a lab
  that already has that Secret reuses it rather than rotating the
  password out from under an operator who already has it (and does not
  reprint it, since it no longer knows the value).
