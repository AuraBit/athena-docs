# Terraform CI Pipeline Design

* Tool: Terraform CI pipeline design (plan-on-PR, apply-on-merge)
* Summary: A green apply proves Terraform did what its plan said, never that the resource is actually there, so this pipeline verifies every apply with an independent describe call in the same job
* Phase introduced: 02-core-network-terraform-ci-verification-pattern
* Related ADRs: athena-infra/docs/adr/0007-promotion-via-pull-request-and-per-environment-module-pinning.md, athena-infra/docs/adr/0008-concurrency-granularity-per-stack-and-environment.md, athena-infra/docs/adr/0006-ci-06-trust-boundary-amendment.md
* Last reviewed: 2026-08-04

## Mental model

This pipeline treats a Terraform change the way a regulated shop treats
any production infrastructure change, a reviewed plan before merge, a
gated apply after it, and independent proof afterward that the apply did
what it claimed. Every design choice in `terraform-core-network.yml`
traces back to one of those three moments.

## Common interview questions

**Why plan on the pull request and apply on merge, rather than applying
from a pull request?** Applying unreviewed code is not something I am
willing to do, full stop, so `plan` only ever runs on the pull request
and `apply` only ever runs after merge to `main`. The plan job posts its
output as a sticky comment a human actually reads before approving, and
that comment is the review artifact, not a rubber stamp on a title.

**How do you stop two merges racing on one state file, and what is the
honest distinction between what the concurrency group guarantees and
what the state lock guarantees?** The `apply` job declares a
`concurrency` group named `terraform-core-<environment>`, so two apply
runs for the same environment never run at the same time, I proved that
live in the concurrency-queue drill. What that group does not guarantee
is that arrival order is apply order, GitHub only holds one pending run
per group, so a third arrival supersedes the pending one rather than
queueing behind it. The control that actually stops two applies writing
state at once is the S3 native lock, `use_lockfile = true`. The
concurrency group is what keeps runs from piling onto that lock in the
first place, and both matter, but only one of them is an ordering
promise.

**Why is the concurrency block declared on the apply job rather than at
workflow level, and what breaks if you get that wrong?** A workflow-level
block applies to every job in the file, including `plan`. That means a
pull request's plan for dev would sit queued behind an unrelated
in-progress apply for dev, which defeats the entire reason I sized the
runner pool to two instances in the first place. I declare the block
inside `apply` only, and I proved the difference matters live, drill
scenario 3 dispatched a held apply and opened a real pull request whose
plan job reached running within about a minute, never queued behind the
apply's own group.

**Why one aggregated required check rather than listing each matrix
leg?** A matrix leg for an environment nobody touched in a given pull
request is skipped, not reported, because `detect-changes` only fans the
plan matrix out to environments that actually changed. A required check
that never reports leaves the pull request pending forever, GitHub has no
way to satisfy a required check that a run never produced. So I need one
check that always reports, the `gate` job, and that job internally
distinguishes an intentional skip, an environment nobody touched, from a
run that was supposed to happen and did not.

**Why a hosted runner for static analysis and a self-hosted runner only
for jobs that need the local emulator?** I run `static`, `fmt`,
`validate`, and Checkov on `ubuntu-latest`, because none of them ever
touch `localhost:4566`. I put `plan`, `apply`, and the `terraform test`
module job on the self-hosted runner, because only that runner can reach
LocalStack at all. Keeping static analysis off the self-hosted runner
minimizes what actually needs to trust that machine.

**How do you let pull requests reach a self-hosted runner without
opening the pwn-request path?** I amended CI-06 in ADR-0006, from
protected-branch-pushes-only to trusted-contexts-only, and the guard is
one boolean, `github.event.pull_request.head.repo.full_name ==
github.repository`. A same-repo branch can only exist because someone
with write access pushed it here, and that same person could already
push straight to `main` and reach the self-hosted runner that way. So
admitting same-repo pull requests changes when a trusted person's code
runs, not who can run it. A fork pull request's head repository is never
equal to this one, so the condition evaluates false and the job never
runs, no exceptions.

**Why is a green apply not evidence the resources exist?** Because
`terraform apply <planfile>` applies exactly the saved plan graph, and it
does not re-verify resources the plan already decided not to touch. I
independently confirmed this project's own local AWS emulator reports
services as available that are in fact license-gated and fail on every
real call, so I never trust a green apply step on its own, anywhere in
this estate.

## Gotchas hit in this project

**`gate`'s skip-handling had to distinguish two different meanings of
"skipped" that GitHub itself does not distinguish cleanly.** A job whose
own `if:` is true but whose matrix evaluates to an empty array reports
`failure`, not `skipped`, on this GitHub Actions version, while a job
whose `if:` genuinely evaluates false, the fork-PR case, reports
`skipped` correctly. `gate`'s aggregator has to know which case it is
looking at using its own `detect-changes` output, not GitHub's raw
result string alone.

**The action version investigation surfaced a real organisation-wide
constraint before this workflow could even run.** The org enforces SHA
pinning for every third-party action, so I had to resolve every `uses:`
line to an immutable commit SHA via a real API call against the upstream
repository before this workflow's first run, and a workflow using an
unresolved tag fails at the allowlist, not at runtime.

**The endpoint override needed to run this workflow's plan job under
`act` is not optional, and it is different from every other job in this
estate.** `act`'s workflow container runs inside its own Docker network
namespace by default, where `localhost` means the container, not the
host, so reaching LocalStack from inside `act` needs `--network host`
explicitly, documented in `docs/runbooks/runner-ops.md`. The `apply` job
is excluded from `act` entirely by design, by choice, not by omission.

## War stories

I independently confirmed that this project's own local AWS emulator
reports services as available that are in fact license-gated and fail on
every real call, which is exactly the fake-success failure class IAC-04
exists to catch. So `scripts/verify-network.sh` calls real `describe`
operations against every resource the stack claims to have created,
compares identifiers exactly, and fails the run when they do not match.
I did not trust that guard until I watched it fail for real, I deleted a
resource directly against LocalStack, bypassing Terraform entirely, right
after the same run's own `terraform apply` step had already reported
success, and the pipeline came back exactly as designed, apply step
green, job red, `verify-network.sh` naming the missing resource by name.
Naming that live run, not just describing the control in the abstract,
is the difference between a control I built and a control I have
actually watched catch something.

## Command cheat-sheet

```bash
gh run view <run-id> --repo AuraBit/athena-infra
gh workflow run terraform-core-network.yml -f drill_env=dev -f drill_hold_seconds=0
. scripts/tf-env.sh dev
act pull_request -W .github/workflows/terraform-core-network.yml -j plan --network host
bash scripts/drills/fake-success-drill.sh
```
