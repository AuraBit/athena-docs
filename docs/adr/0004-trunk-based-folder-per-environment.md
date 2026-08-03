# 0004. Trunk-Based Development with Folder-per-Environment

* Status: accepted
* Date: 2026-08-03
* Deciders: Yahia Tarek (YahiaEng)
* Tier: full-madr

## Context and Problem Statement

Every repo in the estate needs one promotion model: how dev, stg, and prod
each get their own configuration/manifests while staying reconcilable
against a single source of truth, and how a change to that source of truth
gets approved before it reaches a higher-risk environment. The model must
work uniformly across `athena-gitops` (ArgoCD-watched manifests),
`athena-infra` (Terraform per-environment state), and any future
environment-scoped configuration — and it must not silently reintroduce
drift, the exact failure class GitOps exists to eliminate.

## Decision Drivers

* GitOps reconciliation requires exactly one thing an environment's
  running state should be compared against — anything that lets that
  comparison target drift between branches undermines the entire model.
* The promotion path (how a change reaches stg/prod) needs a clean,
  reviewable diff at the point of approval, and a durable audit trail of
  what was approved and when.
* Every one of the estate's repos protects only `main` (see the governance
  ADR) — the promotion model must be consistent with a single protected
  branch, not assume per-environment branch protection exists.
* Reversibility matters here specifically: this decision, once built out
  across four repos' workflows and branch-protection wiring, is costly to
  reverse — restructuring it later touches every repo, every workflow
  trigger, and the entire branch-protection/Environments surface.

## Considered Options

* **Branch-per-environment** (`dev`, `stg`, `prod` as long-lived branches,
  promotion via merge/cherry-pick between them).
* **Folder-per-environment** on a single trunk branch. (Chosen.)
* **A separate repository per environment.**

## Decision Outcome

Chosen option: **"Trunk-based development with folder-per-environment,"**
implemented as `envs/dev|stg|prod` directories in `athena-gitops` and
per-environment directories with separate Terraform state in
`athena-infra`, with every repo protecting `main` only — because it is the
only option that gives GitOps reconciliation a single, unambiguous source
of truth per environment (a folder's current content) without introducing
inter-branch drift, and because a promotion is a reviewable commit diff
rather than a merge/cherry-pick operation whose semantics differ from a
normal code review.

### Consequences

* Good, because ArgoCD (Phase 3+) reconciles each environment against its
  own folder's committed content — there is never a question of "which
  branch is prod actually tracking right now," because there is only one
  branch.
* Good, because a promotion is an ordinary, reviewable commit — the diff an
  approver sees in a stg/prod-gated promotion job (`athena-gitops`
  ADR-0001) is exactly the change being promoted, not a merge conflict
  resolution or a cherry-pick's implicit context loss.
* Good, because the same folder-per-environment shape extends cleanly to
  `athena-infra`'s per-environment Terraform state directories, giving the
  estate one consistent promotion mental model across both repos.
* Bad, because reversing this decision later is costly: switching to
  environment branches would restructure all four repositories, every
  workflow trigger currently written against `main`-only protection, and
  the entire branch-protection/Environments wiring this phase already
  built. This reversibility cost is stated explicitly, not left implicit.

## Pros and Cons of the Options

### Branch-per-environment

* Good, because it is a familiar pattern many teams start with, and
  `git diff dev..prod` gives an at-a-glance view of what's pending
  promotion.
* Bad, because it is a **documented GitOps anti-pattern** for concrete,
  recurring reasons: branches drift from each other over time as
  environment-specific hotfixes land directly on one branch and never get
  back-merged; promotion becomes cherry-pick-driven, which loses commit
  context and risks silently dropping a change; and the inter-branch diff
  becomes permanent and ever-growing rather than resolving to zero, which
  is the opposite of what a promotion model should produce.
* Bad, because it multiplies the reconciliation target ambiguity GitOps is
  supposed to eliminate — ArgoCD would need to track a specific branch per
  environment, and a manual branch-tracking misconfiguration becomes a
  silent, hard-to-detect failure mode.

### Folder-per-environment (chosen)

* See Decision Outcome and Consequences above.

### A separate repository per environment

* Good, because it gives the strongest possible isolation — a compromised
  or misconfigured dev repo cannot directly affect prod's repository at
  all.
* Bad, because it multiplies the four-repo topology (ADR-0003) by three
  environments, producing a repository count this project's topology
  decision already rejected as unnecessary boilerplate for the equivalent
  service-count multiplication.
* Bad, because promoting a change would require a cross-repository
  operation (open a PR against a *different* repo) rather than a single
  reviewable commit in one place — a materially worse reviewer experience
  than a folder diff in one repo, with no corresponding security benefit
  this project's threat model identifies as necessary at this scale.
