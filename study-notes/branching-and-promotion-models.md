# Branching and Promotion Models

* Tool: Branching strategy and promotion gating (trunk-based, folder-per-environment)
* Summary: Promotion is a question about where the difference between environments lives — in branches, in folders, or in parameters
* Phase introduced: 01-local-foundations-repo-governance
* Related ADRs: athena-docs/docs/adr/0004-trunk-based-folder-per-environment.md, athena-app/docs/adr/0001-merge-queue-on-the-app-monorepo-only.md, athena-gitops/docs/adr/0001-folder-per-environment-and-the-promotion-gate.md
* Last reviewed: 2026-08-03

## Mental model

Promotion is fundamentally a question about where the difference between
environments lives — encoded in long-lived branches, in folders on one
trunk, or in parameters resolved at deploy time — and that choice
determines what "drift" even means for the pipeline built on top of it.

## Common interview questions

**Trunk-based vs. GitFlow — what does each optimise for?** Trunk-based
optimises for one continuously-integrated source of truth with small,
frequently-merged changes and minimal long-lived divergence. GitFlow (and
its relatives) optimise for isolating in-progress feature work behind
longer-lived branches, at the cost of larger, riskier eventual merges and a
more complex branch topology to reason about.

**Why is branch-per-environment a documented GitOps anti-pattern?**
Environment branches drift from each other over time as environment-specific
hotfixes land directly on one branch and never get back-merged; promotion
becomes cherry-pick-driven, which loses commit context and risks silently
dropping a change; and the inter-branch diff becomes permanent and
ever-growing instead of resolving to zero — the opposite of what a
promotion model should produce. It also multiplies GitOps's own
reconciliation-target ambiguity: "which branch is this environment actually
tracking right now" becomes a real, silently-misconfigurable question
instead of not existing at all.

**Where does a merge queue help, and where does it just add latency?** It
helps where multiple PRs can legitimately merge close together and their
*combined* result needs verifying, not just each one in isolation — a
monorepo with path-filtered CI, for example. It just adds latency on a path
with no multi-PR-combination risk to protect: a fast-moving, bot-authored
commit path, or a repository whose own concurrency risk is already solved
at a different layer entirely (Terraform applies serialized by
concurrency groups, not by combining PRs).

**How do you gate production without blocking developers?** Bind the gate
to the specific job that performs the risky write — the promotion-commit
job, or the `terraform apply` job — via a GitHub Environment with required
reviewers, not to the PR/branch-protection layer, which governs a different
and earlier question (getting a change into `main` at all). This lets
ordinary development keep moving at full speed while only the
promotion-write itself pauses for approval.

**What does continuous deployment require that continuous delivery does
not?** CD requires the pipeline to actually perform the production deploy
automatically once checks pass, with no human-in-the-loop gate anywhere.
Continuous delivery keeps the release deployable at all times but still
requires an explicit trigger — often a human approval — to actually ship
it. This project's stg/prod Environment gates make it continuous delivery,
not full continuous deployment, by deliberate design.

## Gotchas hit in this project

**A merge queue on a bot-driven commit path adds latency for no safety
gain.** This is exactly why only `athena-app` (the monorepo with genuine
multi-PR-combination risk across concurrently-merging service changes)
carries a native GitHub merge queue, while `athena-gitops` (whose
promotion-commit path needs to stay fast) and `athena-infra` (whose
serialization need — preventing concurrent `terraform apply` runs against
the same state — is solved by Actions concurrency groups, a mechanism
suited to protecting a single shared resource rather than combining
independent PRs) both deliberately stay queue-free.

## War stories

**The drift, cherry-picking, and permanent inter-branch diffs that
branch-per-environment produces** is the textbook GitOps anti-pattern
story — this estate's own folder-per-environment layout
(`envs/dev|stg|prod/` on a single protected `main`) plus its
promotion-commit-job gate (the job that writes to `envs/stg/` or
`envs/prod/` is what pauses for a `team-platform` reviewer's approval, not
ArgoCD itself, whose auto-sync stays on everywhere so Phase 3's
drift-revert demonstration keeps working) is the concrete alternative
actually built here, specifically to avoid two branches ever disagreeing
about what "prod" currently means.

## Command cheat-sheet

```bash
gh api repos/AuraBit/athena-app/rulesets --jq '.[] | {name, rules: [.rules[].type]}'
gh api repos/AuraBit/athena-app/environments --jq '.environments[].name'
gh api repos/AuraBit/athena-app/merge-queue 2>/dev/null || echo "no active queue entries"
```
