# providers/

One Terraform root module per cloud, each with exactly one job: produce
SSH-reachable Ubuntu VMs and hand back a small, fixed set of outputs.
Nothing past that point (installing Kubernetes, the CNI, the
`clusterdrill` package) is cloud-specific - see
[`../bootstrap/`](../bootstrap/), which consumes any provider's outputs
identically. See [`../docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md) for a
diagrammed view of how this fits into the whole system.

## The common output contract

Every `providers/<cloud>/` module must produce exactly these outputs:

| Output | Type | Meaning |
| --- | --- | --- |
| `control_plane_ip` | string | Public (or otherwise SSH-reachable) IP of the control-plane node. |
| `worker_ips` | list(string) | Public (or otherwise SSH-reachable) IPs of the worker nodes. |
| `ssh_user` | string | SSH username every node uses. |
| `ssh_key_name` | string | An identifier for the key pair the nodes were launched with - not the key material itself. No provider module generates, stores, or outputs a private key. |

`bootstrap/` only ever reads these four values - it has no `aws_*`,
`gcp_*`, or any other cloud-specific code, environment variable, or
metadata-service call anywhere in it. Verify this yourself with
`grep -ri aws bootstrap/` before trusting that claim - it should be
clean.

## Providers

- **`aws/`** - built first, the only one that actually provisions
  infrastructure today. See its own [README](aws/README.md).
- **`gcp/`** - a documented, reserved seam, not implemented. Building it
  before anyone needs it would be exactly the kind of premature
  abstraction this project avoids - when it's needed, it's "write
  `providers/gcp/*.tf` producing the same four outputs," not a rewrite
  of anything else in this repository.

## Cross-provider version parity (placeholder)

Whether a future second provider module must track the same Kubernetes
minor/Cilium/Ubuntu pins as `aws/`'s `compatibility.json` snapshot, or is
allowed to diverge and publish its own, is not yet decided - low urgency
since `gcp/` isn't built, but flagged here so the question has a home
once someone actually builds it, rather than being silently unanswered.
See [`MAINTAINING.md`](../MAINTAINING.md) for how `aws/`'s own pins are
versioned today.
