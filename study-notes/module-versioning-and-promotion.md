# Module Versioning and Promotion

* Tool: Terraform module versioning and environment promotion (git-tag pinning)
* Summary: A module version is a promise that a named resource set is stable enough to pin against, and promotion is one reviewed pull request bumping one environment's own reference
* Phase introduced: 02-core-network-terraform-ci-verification-pattern
* Related ADRs: athena-infra/docs/adr/0007-promotion-via-pull-request-and-per-environment-module-pinning.md
* Last reviewed: 2026-08-04

## Mental model

A module version is a promise, not a snapshot, it says the resource set
and the output names behind this tag are stable enough that an
environment can pin against them without checking again every time. In
this estate that promise is a git tag, `modules/core-network/v1.0.0`, cut
only once the tagged commit has already passed the module's own tests and
the static gate on `main`.

## Common interview questions

**How do you promote a change through environments?** Promoting an
environment is a one-line pull request, bumping that environment's own
`?ref=` argument in its `main.tf` to a newer module tag. I did this three
times for real in Plan 02-08, dev first, then stg, then prod, each its
own pull request with its own plan and its own review, and each merge
triggering that one environment's own apply. Nothing about promoting stg
touches dev's or prod's files at all.

**Why per-environment module pins rather than a multi-stage pipeline?**
I want to state the multi-stage shape fairly before I reject it here,
because an interviewer with an Azure DevOps background has probably run
it personally. One pipeline, one commit, multiple gated stages, dev then
stg then prod, each stage promoting the exact same build artifact
unchanged, gives me one timeline for the whole promotion and a guarantee
that what passed dev is bit-for-bit what reaches prod. That is the right
shape for a single deployable artifact, a container image or a compiled
binary, moving through environments unchanged. It loses here on one
structural fact, not on being old-fashioned, this repository has no
single artifact to promote. I run three independent Terraform roots,
`envs/dev/core-network`, `envs/stg/core-network`, and
`envs/prod/core-network`, each with its own state, each free to pin a
different module version at any moment. A pipeline that assumes one build
moving through gates in lockstep does not match a layout where each
environment's pinned reference is its own fact, changed on its own
schedule.

**Why git tags rather than relative paths, and what specifically breaks
with relative paths?** A relative path like `../../../modules/core-network`
resolves against whatever happens to be on `main` at apply time, not
against a version anyone reviewed. If I used a relative path in every
environment root, dev and prod would silently run identical code the
moment the module changed on `main`, with no pull request marking the
moment prod actually moved to new code. The promotion pull request that
was supposed to be the audit trail becomes a no-op nobody notices.
Pinning by tag makes that impossible by construction, an environment's
code only changes when its own `?ref=` line changes, and I only ever
change that line inside a reviewed pull request.

**When would you reach for a private module registry instead?** I would
reach for one the moment this estate needs to share modules outside this
one repository, or wants registry-level version constraints and
provenance metadata beyond what a git tag carries. Git-tag pinning
already gives me every property this phase's requirements need, an
immutable, reviewable, per-environment reference. A registry adds real
operational surface, hosting, publishing credentials, a second place
versions can drift from the tag that produced them, that I do not yet
need to carry here.

**How do you roll a promotion back?** I use the identical mechanism run
in reverse, another pull request, pinning the previous tag, reviewed and
merged through the exact same pipeline as any other promotion. There is
no separate rollback pipeline and no direct state edit. A rollback is an
ordinary promotion pull request whose diff happens to move the ref
backwards instead of forwards, subject to the same plan review and the
same human-approval gate on stg and prod as any other promotion.

## Gotchas hit in this project

**A tag has to exist before an environment can initialize against it, a
genuine chicken-and-egg.** I could not write stg's `main.tf` pointing at
`modules/core-network/v1.0.0` and run `terraform init` until that tag was
already pushed to `origin`, so cutting the release always has to happen
first, as its own step, before any environment's promotion pull request
can even be opened, not something I can batch together after the fact.

**Dev's version-one ref bump showed zero resource replacements, and that
was the correct outcome, not a surprising one.** `v1.0.0` marks the
module feature-complete on content already identical to the previously
applied `v0.6.0`, it does not change any resource, so the promotion
pull request's plan reading "No changes" is exactly what a pure
version-one release tag should show, confirming the ref-bump mechanism
itself introduces no unintended drift, recorded in ADR-0007's own
consequences.

## War stories

The industry failure this control exists for is an environment quietly
running code nobody remembers pinning it to, because a relative import or
an unpinned branch reference let it drift onto `main` without anyone
opening a pull request for it. The concrete control in this estate that
closes that gap is every environment root's `?ref=` pointing at an
annotated git tag, never a path, so `git diff` on one file in one pull
request is a complete, honest answer to the question of what changed in
any given environment, the same audit-trail property `docs/runbooks/module-release-and-promotion.md`
documents as the whole point of the mechanism.

## Command cheat-sheet

```bash
git tag -a modules/core-network/v1.0.0 -m "modules/core-network v1.0.0: ..."
git push origin modules/core-network/v1.0.0
git cat-file -t modules/core-network/v1.0.0   # must print: tag
sed -i 's#ref=modules/core-network/v0.6.0#ref=modules/core-network/v1.0.0#' \
  envs/stg/core-network/main.tf
terraform plan -input=false -no-color   # expect "No changes" for a pure ref bump
```
