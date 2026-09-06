# providers/gcp (reserved seam - not built)

This directory intentionally has no Terraform in it yet. It exists so
the shape of the repository - one root module per cloud, all producing
the same [output contract](../README.md#the-common-output-contract) -
is visible before GCP support exists, without building something nobody
has asked for.

When GCP support is actually needed, this becomes a Terraform root
module (`versions.tf`, `variables.tf`, `main.tf`, `outputs.tf`,
`terraform.tfvars.example`, `README.md`) that provisions one
control-plane and N worker Ubuntu VMs reachable over SSH, and outputs
exactly `control_plane_ip`, `worker_ips`, `ssh_user`, and `ssh_key_name`,
the same four values [`aws/`](../aws/) produces. Nothing in
[`../../bootstrap/`](../../bootstrap/) needs to change to support it.
