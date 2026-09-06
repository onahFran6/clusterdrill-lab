## Summary

<!-- What does this PR change, and why? -->

## Verification

<!-- Paste the output of the relevant command(s) below. -->

- [ ] `terraform fmt -check` and `terraform validate` pass (run from `providers/aws/`, or the relevant provider root module).
- [ ] `shellcheck bootstrap/*.sh` passes, if `bootstrap/` changed.
- [ ] No real cloud credentials, account IDs, or state files are included in the diff.

## Checklist

- [ ] If a Terraform root module's provider version constraints changed, `.terraform.lock.hcl` is updated and committed.
- [ ] New or changed variables have a `description` and, where meaningful, a `validation` block.
- [ ] `terraform.tfvars.example` (or the relevant provider's example file) is updated if variables changed.
- [ ] No cloud-specific assumptions were added to `bootstrap/` (it must stay provider-agnostic - see `bootstrap/README.md`).
