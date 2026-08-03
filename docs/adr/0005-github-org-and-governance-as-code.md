# 0005. GitHub Organisation Over a Personal Account, and Governance as Terraform Code

* Status: accepted
* Date: 2026-08-03
* Deciders: Yahia Tarek (YahiaEng)
* Tier: full-madr

## Context and Problem Statement

The estate's four repositories need a real GitHub presence with team-based
review routing, an org-scoped merge queue, org-level self-hosted runner
registration shared across repos, and org-scoped secrets — none of which a
personal account can provide. That presence, once created, also needs to
be managed reproducibly rather than by hand, with a documented recovery
path if the local machine (and its Terraform state) is ever lost, and with
a clear, honest answer to the identity question every automation needs:
who — or what — actually performs org actions on this solo developer's
behalf, since a lone human cannot approve their own pull requests.

## Decision Drivers

* Team-based CODEOWNERS review routing, GitHub merge queues, and org-scoped
  secrets/runner registration are all org-only GitHub features — a
  personal account cannot host any of them.
* A solo developer cannot approve their own pull requests — some other
  identity must exist to satisfy required-review rules, and that identity's
  authentication mechanism (bot user vs. GitHub App) has real, structurally
  different consequences for how bypass/approval rules must be configured.
* Manually clicking through org/team/repo/branch-protection configuration
  is not reproducible, not diffable, and not the practice this project's
  own interview-value thesis is supposed to demonstrate.
* Some GitHub objects (the org itself, the bot account, the first
  repository) cannot be created by any API at all — the governance design
  needs an honest bootstrap story for that chicken-and-egg gap, not a
  pretense that everything is Terraform-native from step one.

## Considered Options

* **A personal GitHub account** hosting all repositories directly.
* **An org, configured entirely by hand** through the GitHub web UI.
* **An org, configured by ad hoc `gh api`/`gh` CLI scripts.**
* **An org, configured by a Terraform governance stack with a documented
  bootstrap-then-import step for the objects Terraform cannot create.**
  (Chosen.)

## Decision Outcome

Chosen option: **"An org, configured by a Terraform governance stack,"**
under the org login `AuraBit` — the four capabilities that force an org
(team-based CODEOWNERS, merge queues, org-level runner registration, org-
scoped secrets/variables) are non-negotiable requirements a personal
account structurally cannot satisfy, and Terraform is the only option that
gives the estate a diffable, reproducible, re-runnable description of that
org's configuration rather than a one-time manual setup nobody can safely
repeat.

**Note on the originally-planned org login:** the phase context's assumed
login (`athena-platform`) was found live, before any Terraform ran, to
already belong to an unrelated third-party account. `AuraBit` was created
fresh and confirmed developer-owned before proceeding — a corrected
identity, not a change of design; every rationale in this ADR is otherwise
unaffected.

### Bootstrap-then-import

Three objects cannot be created by any Terraform provider, because no
GitHub API exists to create them programmatically: the organisation itself
(a UI-only, account-holder-driven flow), the machine account (requires a
real email-verification loop a script cannot complete), and the first
repository, `athena-infra` (it must exist empty before it can hold the
Terraform code that will manage everything else — the code cannot live in
a place that doesn't exist yet). These three are created by hand once, then
adopted into Terraform state via `terraform import`, with the success
condition that the following `terraform plan` reports zero changes. Every
other repository, team, membership, and grant is created entirely by
`terraform apply` with no further manual steps. This bootstrap procedure
is documented in full in `athena-infra/docs/runbooks/github-bootstrap.md`.

### Machine account vs. GitHub App (user-requested addition)

A deliberate, explicit choice, not a default: the bot identity
(`athena-ci-bot`) is a **plain GitHub user account**, not a **GitHub App**.
The two are structurally different and the wrong choice would have quietly
broken the approval flow:

* A **GitHub App** authenticates with short-lived, automatically-rotated
  installation tokens — materially better credential hygiene, since there
  is no long-lived PAT to leak or rotate by hand. But an App **cannot** be
  an org owner, cannot be a team member, cannot appear in a CODEOWNERS
  file, and cannot be a PR "approver" identity in the same sense a human or
  bot user can — its reviews and comments are attributed to the App's
  identity, but it does not hold org-owner-level authority the way D-03's
  design requires (the bot needing to approve PRs the solo developer
  cannot self-approve).
* A **machine account (bot user)** can be invited as an org owner, added to
  teams, listed in CODEOWNERS, and act as a genuine PR-approver identity —
  everything D-03's design needs. The cost is a long-lived PAT that must be
  stored, scoped, and eventually rotated by hand (or by a future secrets
  system), and its `bypass_actors.actor_type` must be declared as `User`,
  not `Integration` — a distinction this project confirmed live and
  documents as a solved pitfall in `athena-infra/docs/runbooks/
  github-bootstrap.md`, since RESEARCH.md's generic example assumed the
  `Integration` value.

`athena-ci-bot` is a machine account **because** D-03's design specifically
needs an org-owner-level, CODEOWNERS-eligible, PR-approving identity — a
capability only a user account (human or bot) has. This is recorded as the
correct choice for *this phase's* need, not a rejection of GitHub Apps in
general.

**Intended future migration (not yet built):** the automation
*credentials* this bot account currently holds (`GITHUB_TOKEN` for
Terraform auth, `GH_RUNNER_REG_PAT` for runner registration) are a natural
candidate to migrate from long-lived bot PATs to a GitHub App's short-lived
installation tokens in a later phase — specifically when Vault (Phase 5)
takes over secrets management and rotation-aware patterns become the
estate's own practiced discipline. The bot account's *identity* (its role
as the CODEOWNERS-eligible, PR-approving org-owner user) would remain a
user account regardless, since that structural requirement doesn't change;
only the *credential-issuance mechanism* backing automated actions would
move to the App model. This is a forward-looking design note, not a
commitment executed in this phase.

### Consequences

* Good, because the entire org configuration is diffable, re-runnable, and
  survives a lost local machine via the documented bootstrap-then-import
  recovery path.
* Good, because the machine-account-vs-App tradeoff is now a resolved,
  documented decision — a later phase reconsidering credential hygiene has
  a clear starting point rather than re-litigating the identity question
  from scratch.
* Bad — and this reversibility rating is stated explicitly per this
  project's ADR conventions — the org identity is baked into module paths,
  image references, repository URLs, and every document across the estate.
  Migrating to a different org login later would touch all of them; this
  decision is **one-way in practice**.
* Bad, because the bot's long-lived PAT is a real credential-hygiene cost
  that a GitHub App would have avoided — accepted for this phase given the
  App's structural incompatibility with D-03's approval-identity
  requirement, with the migration path above recorded as the honest
  answer to "wouldn't a GitHub App be better here?"

## Pros and Cons of the Options

### A personal GitHub account

* Good, because it requires zero org-level setup at all.
* Bad, because it structurally cannot provide team-based CODEOWNERS, merge
  queues, org-scoped secrets, or org-level runner registration — a
  disqualifying gap against this project's own stated requirements.

### An org, configured entirely by hand

* Good, because it requires no Terraform provider knowledge and no
  bootstrap-then-import complexity.
* Bad, because it is not reproducible, not diffable, and not re-runnable —
  exactly the practice gap this project's interview-value thesis exists to
  close, not model.

### An org, configured by ad hoc `gh api`/`gh` CLI scripts

* Good, because it is scriptable and more reproducible than pure clicking.
* Bad, because it reinvents diffing/drift-detection logic the
  `integrations/github` Terraform provider already solves — the exact
  class of problem Terraform exists for, per this project's own
  "Don't Hand-Roll" research finding.

### An org, configured by a Terraform governance stack (chosen)

* See Decision Outcome and Consequences above.
