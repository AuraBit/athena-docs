# Terraform GitHub Provider Governance

* Tool: Terraform (integrations/github provider)
* Summary: An organisation is infrastructure — the org, its teams, repos, and rulesets are managed by the same declare-and-reconcile discipline as a VPC
* Phase introduced: 01-local-foundations-repo-governance
* Related ADRs: athena-docs/docs/adr/0005-github-org-and-governance-as-code.md
* Last reviewed: 2026-08-03

## Mental model

An organisation is infrastructure: GitHub org settings, teams, repositories,
and branch rulesets are all just another API surface with real
create/read/update/delete semantics, so the same "declare desired state,
reconcile against it" discipline Terraform applies to a VPC applies equally
to a GitHub org — the `integrations/github` provider handles the diffing
and drift-detection, the same class of problem Terraform exists to solve.

## Common interview questions

**What belongs in Terraform, and what does not?** I put anything in
Terraform that has an API genuinely supporting declarative create, read,
update and delete — org settings, teams, repositories, branch rulesets,
Environments all qualify. What has no API at all, I cannot Terraform no
matter how badly I want to. This estate hit three of those: creating the
org itself, verifying a bot account's email, and standing up the very
first empty repository that would eventually hold the Terraform code
managing everything else. Each of those gets a documented
bootstrap-then-import step instead of a workaround, because pretending an
API exists where it does not is the actual mistake, not the manual step
itself.

**How do you bring an existing hand-created resource under management?** I
run `terraform import`, and then I treat a subsequent `terraform plan`
reporting zero changes as the actual success condition, not the import
command itself exiting zero. If that plan still shows a diff, my `.tf`
code does not accurately describe what got hand-bootstrapped, and that is
a real configuration mismatch, not a cosmetic one. Left alone, a mismatch
like that either drifts silently or gets clobbered on the next `apply`, so
I do not consider an import finished until the plan comes back clean.

**What do you do when the provider doesn't cover a feature?** First I work
out which kind of gap I am looking at. A coverage gap means the field or
behavior exists in the API or UI but no provider resource or argument
exposes it at the version I have pinned. For that kind, I name the gap
explicitly, write a small idempotent script next to the `.tf` it
compensates for, and recheck it every time the provider version bumps. A
total API gap means nothing exists for any provider or any `gh api` call
to reach at all. This estate hit exactly one of those:
fork-PR-approval-for-outside-collaborators has zero REST or GraphQL
surface, confirmed by exhaustively probing every plausible endpoint path
and running a GraphQL schema introspection. For a total gap there is no
script to write. I record it honestly as a genuine, permanent manual step
instead of faking it as Terraform-managed.

**Why is state location a design decision rather than a default?** Because
state's job is to describe what actually exists, and its durability has to
match the durability of the thing it describes. State that outlives the
resources it describes is drift, and state that dies with resources that
persist is data loss, so I cannot pick one uniform answer and call it
done. This estate is the concrete case: I have two Terraform stacks whose
resources have genuinely different lifetimes, and a single backend choice
is provably wrong for at least one of them, which is exactly what I work
through in the war story below.

## Gotchas hit in this project

**The ruleset bypass-actor type differing between a bot user account and an
app integration fails silently.** `bypass_actors.actor_type` must match
*how the identity actually authenticates* — `"User"` for a plain GitHub
user account, `"Integration"` for a GitHub App. Get it wrong and there's no
obviously-wrong error: the merge simply stays blocked with a generic
"required review not satisfied" message, with nothing pointing at the
actual cause. The value that actually worked here: `athena-ci-bot` is a
plain user account, so `actor_type = "User"`, `actor_id = 312349166` — not
the `actor_type = "Integration"` an initial research pass assumed before
this project's bot's real account type was confirmed live.

## War stories

**The state-locality principle, worked out concretely across this
project's own two Terraform stacks.** The governance stack's state (the
org, teams, repos) is a local file, git-ignored and backed up outside git,
because it describes a real, persistent GitHub org that outlives every
local restart — losing that state would mean losing track of infrastructure
that still genuinely exists. The AWS-emulation stacks' state (Phase 2+)
lives inside LocalStack's own S3 instead, deliberately, because those
resources exist only inside an ephemeral, free-tier LocalStack process that
loses its own internal state on every restart — keeping Terraform's state
*inside* that same ephemeral boundary means a restart wipes state and the
resources it describes **together**, into one coherent fresh world, rather
than leaving state that claims resources exist which a fresh LocalStack
process has never heard of. A single uniform backend policy ("always
local" or "always remote") is provably wrong for one of the two stacks no
matter which way you pick it — this is the concrete worked example for
"where should Terraform state for this project live, and why isn't the
answer uniform."

## Command cheat-sheet

```bash
terraform import github_organization_settings.this <numeric-org-id>
terraform plan -detailed-exitcode   # 0 = no changes, 2 = changes pending
terraform state list
terraform plan -target=github_repository_ruleset.app_main
```
