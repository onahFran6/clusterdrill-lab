# Governance

ClusterDrill Lab is currently maintained by a single maintainer
([`.github/CODEOWNERS`](.github/CODEOWNERS) is the source of truth for
who that is) - there is no formal committee, voting process, or
multi-maintainer consensus model yet. This document says what that means
in practice, so contributors know what to expect rather than assuming a
process that doesn't exist.

## Decision-making

The maintainer has final say on what gets merged, including infrastructure
design, provider support, and scope decisions. Design discussion happens
in the open (issues, PRs, [Discussions](../../discussions)) and
contributor input is genuinely considered, but there's no formal RFC or
vote - this is a benevolent-maintainer model, not a democracy.

## Provider scope decisions

Adding support for a new cloud provider (see `providers/gcp/`'s reserved,
not-yet-built seam) is a maintainer decision, not something an individual
PR can unilaterally decide to start - open an issue to discuss scope
before sending a large provider-implementation PR.

## Becoming a maintainer

Not currently a formalized path - reach out if you've made sustained,
substantive contributions and are interested. This section will be
expanded if and when the project grows beyond one maintainer.

## Changing this document

Governance changes go through the normal PR process like anything else -
there's no special ratification procedure while there's a single
maintainer.
