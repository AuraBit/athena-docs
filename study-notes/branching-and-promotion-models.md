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

**Trunk-based vs. GitFlow — what does each optimise for?** I'd say
trunk-based optimizes for one continuously-integrated source of truth,
with small, frequently-merged changes and minimal long-lived divergence.
GitFlow and its relatives optimize for something different: isolating
in-progress feature work behind longer-lived branches. That isolation
costs you larger, riskier eventual merges and a branch topology that takes
more effort to reason about, and this estate picked trunk-based
deliberately to avoid paying that cost.

**Why is branch-per-environment a documented GitOps anti-pattern?** I've
watched this fail in three separate ways, and branch-per-environment
produces all three. First, environment branches drift from each other
over time, because environment-specific hotfixes land directly on one
branch and never get back-merged into the others. Second, promotion turns
into a cherry-pick exercise, which loses commit context and risks silently
dropping a change nobody meant to drop. Third, the inter-branch diff
becomes permanent and keeps growing instead of resolving to zero, which is
the exact opposite of what a promotion model is supposed to produce. On
top of those three, it multiplies GitOps's own reconciliation-target
ambiguity: the question of which branch an environment is actually
tracking right now becomes a real, silently-misconfigurable question
instead of one that doesn't exist at all.

**Where does a merge queue help, and where does it just add latency?** I
reach for a merge queue where multiple pull requests can legitimately
merge close together and their combined result, not just each one in
isolation, genuinely needs verifying. A monorepo with path-filtered CI is
exactly that case. It just adds latency where there is no
multi-PR-combination risk to protect at all. A fast-moving, bot-authored
commit path is one example of that. This estate's own Terraform stack is
another: its concurrency risk is already solved at a different layer,
applies serialized by concurrency groups rather than by combining PRs, so
a queue there would only add wait time for nothing.

**How do you gate production without blocking developers?** I bind the
gate to the specific job that performs the risky write, the
promotion-commit job or the `terraform apply` job, using a GitHub
Environment with required reviewers. I do not bind it to the PR or
branch-protection layer, because that layer governs a different, earlier
question: whether a change gets into `main` at all. Binding it this way
lets ordinary development keep moving at full speed, and only the
promotion-write itself pauses for approval.

**What does continuous deployment require that continuous delivery does
not?** Continuous deployment requires the pipeline to perform the
production deploy automatically once checks pass, with no human in the
loop anywhere. Continuous delivery is different. It keeps the release
deployable at all times but still requires an explicit trigger, often a
human approval, to actually ship it. This estate's stg and prod
Environment gates make it continuous delivery, not full continuous
deployment, and I designed it that way deliberately.

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
