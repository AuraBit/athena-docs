# 0003. Repository Topology

* Status: accepted
* Date: 2026-08-03
* Deciders: Yahia Tarek (YahiaEng)
* Tier: full-madr

## Context and Problem Statement

The estate needs a real GitHub repository topology capable of exercising
concurrency queues, GitHub Environments with required reviewers, branch
protection, CODEOWNERS, and real ArgoCD pulls — none of which can be
exercised in local simulation. The topology choice shapes every later
phase's CI design, and it needs to teach the *harder* problems (change
detection across a monorepo, path-filtered CI, cross-service interaction
risk) rather than the easier ones a naive split would produce.

## Decision Drivers

* Real GitHub Environments, branch protection, required reviewers, merge
  queues, and ArgoCD pulls all require actual separate repositories — no
  amount of local tooling substitutes for them.
* The chosen split should maximize the interview-relevant CI problems
  solved (change detection, selective build/test/deploy, cross-service
  interaction risk) rather than avoid them.
* A documentation surface (estate-level ADRs, architecture diagrams,
  interview study notes) needs a home that is neither inside a delivery
  repo (where it would compete with that repo's own purpose) nor absent
  entirely.
* Whatever topology is chosen should be justifiable as a real trade-off a
  competent interviewer would recognize, with the rejected alternative's
  cost stated honestly.

## Considered Options

* **Repo-per-service** — one repository per microservice (roughly a dozen
  for the Athena app alone).
* **A single mega-repo** — app, infra, and gitops manifests all in one
  repository.
* **App monorepo + infra repo + gitops repo (three-repo topology), plus a
  fourth documentation-only handbook repo.** (Chosen.)

## Decision Outcome

Chosen option: **"App monorepo + infra repo + gitops repo, plus a
documentation-only fourth repo,"** because it is the only option that
exercises the harder monorepo CI problems (path-based change detection,
selective builds, merge-queue interaction risk across concurrently-merging
service changes) while still giving Terraform, GitOps, and app code each
their own real branch-protection/Environments/CODEOWNERS surface —
something a single mega-repo cannot cleanly provide, since Terraform applies,
GitOps promotions, and app CI have fundamentally different concurrency and
review needs that a single repo's rulesets can't express independently.

### Consequences

* Good, because `athena-app`'s monorepo CI must solve real change
  detection and selective build/test/publish across polyglot services —
  directly the harder, more interview-relevant CI problem repo-per-service
  would have avoided entirely.
* Good, because `athena-infra` (Terraform, governance-as-code) and
  `athena-gitops` (ArgoCD-watched manifests) each get independently-tuned
  branch protection, merge concurrency behaviour, and review requirements
  matched to their actual risk profile (see `athena-app` ADR-0001 and
  `athena-gitops` ADR-0001 for the concrete per-repo tuning).
* Good, because `athena-docs` gives estate-level documentation an
  unambiguous home without becoming a fourth delivery path — see "Why a
  fourth repo doesn't violate the three-repo topology" below.
* Bad, because a monorepo's CI tooling (path filters, matrix builds) is
  inherently more complex to author correctly than N independent repos'
  trivial single-service pipelines — accepted because that complexity
  *is* the learning target, not an unwanted cost.

### Why a fourth repo doesn't violate the three-repo topology

The project's stated topology commitment is **three** real delivery repos,
chosen specifically because concurrency queues, Environments, branch
protection, and real ArgoCD pulls justify the overhead of separate
repositories. `athena-docs` is different in kind, not an exception: it
carries **no CI/CD pipeline** and is **not part of the app -> infra ->
gitops delivery loop** — nothing builds, deploys, or promotes through it.
It exists purely as a documentation surface extending what the three
delivery repos already need (estate-wide ADRs, architecture diagrams,
study notes that don't belong inside any single delivery repo) without
adding a fourth delivery path. The three-repo commitment is about
*pipeline* topology; this repo has none, so it does not count against it.

## Pros and Cons of the Options

### Repo-per-service

* Good, because each service's CI is trivially simple — one build, one
  test suite, no change-detection logic needed at all.
* Bad, because it loses the harder, more realistic CI problems this
  project exists to demonstrate — path-based change detection, selective
  matrix builds, and cross-service merge-queue interaction risk simply
  don't arise when every service already has its own repository.
* Bad, because roughly a dozen repositories multiplies boilerplate
  (workflow files, branch protection config, CODEOWNERS, LICENSE, README)
  by a dozen for zero corresponding learning value — most of that
  boilerplate would be identical copy-paste across repos.

### A single mega-repo

* Good, because it is the simplest possible topology — one clone, one
  place to look, no cross-repo coordination at all.
* Bad, because it cannot cleanly express three genuinely different
  concurrency and review models (app CI's merge queue, infra's
  Terraform-apply serialization via concurrency groups, gitops's fast
  bot-commit path) inside one repository's rulesets — GitHub Environments
  and rulesets apply per-repository, not per-directory.
* Bad, because it collapses the real ArgoCD-pull-from-a-separate-repo
  pattern this project specifically wants to demonstrate (GitOps as a
  distinct, watched source of truth) into a single-repo self-reference,
  which is a materially less realistic and less interview-relevant
  pattern.

### App monorepo + infra repo + gitops repo + docs repo (chosen)

* See Decision Outcome and Consequences above.
