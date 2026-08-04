# Terraform State and Locking

* Tool: Terraform state and locking (native S3 lockfile)
* Summary: Remote state plus a lock is what keeps two applies from corrupting one shared file, and the native S3 lockfile is one fewer moving part than the DynamoDB table it replaced
* Phase introduced: 02-core-network-terraform-ci-verification-pattern
* Related ADRs: athena-infra/docs/adr/0009-simulated-account-per-environment-and-state-bucket-per-account.md
* Last reviewed: 2026-08-04

## Mental model

Terraform state is the one file that records what Terraform believes
exists and how every resource it manages maps to a real id, and I treat it
as the single most dangerous file in this whole estate, because two
processes writing it at the same moment can silently corrupt it. A lock is
just a mutual-exclusion flag sitting next to that file, and the entire
point of paying for one at all is turning a silent double write into a
loud, blocked second run instead.

## Common interview questions

**Why remote state at all, instead of a state file on your own laptop?**
I keep state in S3 because this estate has three environments, and a
local state file only works if exactly one machine is ever the source of
truth for what Terraform believes exists. Every environment root in this
estate, `envs/dev/core-network/backend.tf` for example, points its
backend at a bucket named `athena-tfstate-dev`, one bucket per simulated
account. That means anyone with the right credentials runs a plan against
the same state Terraform already knows about, instead of quietly working
from a stale local copy nobody else can see.

**What actually changed when native S3 lockfile locking replaced the
DynamoDB table, and why is that one fewer moving part rather than merely a
different one?** I used to need a whole second AWS service, a DynamoDB
table, purely to hold a lock row while Terraform touched an S3 object.
Terraform 1.11 added `use_lockfile` directly into the S3 backend itself,
so the lock now lives as one more object inside the same bucket the state
already lives in, a lock file sitting next to `terraform.tfstate`. That is
a smaller true statement than a merely different mechanism. It deletes an
entire service dependency, no table to create, tag, protect, or explain
to somebody auditing this estate, and one less thing that can drift out
of sync with the bucket it was meant to protect. My backend block in this
estate has no lock-table argument anywhere, on purpose.

**How do conditional writes actually make the lock atomic?** The
mechanism is S3's own conditional PUT, the `If-None-Match` header.
Terraform writes the lock object with a header that says only succeed if
nothing already exists at that key. S3 either creates it or refuses with
a 412 precondition-failed response, and there is no window where two
writers can both believe they got it. I proved this genuinely holds
against LocalStack, not just assumed it, with
`scripts/verify-tfstate-locking.sh`. It acquires a lock, tries a second
concurrent operation against the same state, and confirms the second one
is refused with that exact error, then confirms the first one's release
removes the object again.

**What is a `.tflock` object, concretely?** It is a small JSON object
Terraform writes at the state key plus a `.tflock` suffix, so for
`core-network/terraform.tfstate` the lock lives at
`core-network/terraform.tfstate.tflock` in that same bucket. Its body
names who holds it, what operation they are running, and when they
started. I read that exact JSON myself during the stale-lock drill, an
id, an operation type of apply, a holder of my own local user, and a
creation timestamp. Terraform's own error message printed those identical
fields back at me when I tried a second operation against the same state.

**Why can't you just apply the plan file the pull request produced?** A
saved plan file records the state serial it was computed against, and
applying that file later fails if state has moved since then. So I
genuinely cannot take what a reviewer looked at on the pull request and
run that exact file after merge. What actually happens in this estate's
merge-triggered apply job is a fresh re-plan, computed right before apply
and applied in the same run. I think of the pull request's plan as the
review artifact and the merge run's own plan as the execution artifact,
because those are two genuinely different plans even when nothing else
changed in between. That costs something real, the plan that actually
gets applied is not the exact plan a human reviewed, and that sounds
worse than it is until I say what this estate does about the gap. Every
apply run writes its own fresh plan summary into that same job's step
summary, so an auditor reading the run afterward sees exactly what was
proposed and applied together, not a green checkmark standing in for a
diff nobody wrote down.

**Why do you never auto-roll-back a failed apply?** A rollback is itself
a state-mutating operation, run against a stack I have just proven I do
not fully understand. The apply that failed is the exact evidence I do
not understand it yet. Destroying whatever got half-created to recover
from a partial creation takes a partial outage and turns it into a
complete one, which is a strictly worse position than the one I started
in. My posture in this estate is fail loud, keep the partial state
exactly as it is, and fix forward with a new plan and apply cycle. That
is the same posture `docs/runbooks/terraform-apply-failure.md` commits
this estate to, and the stale-lock drill's own recovery followed that
identical shape, a new plan and apply against existing state, never a
destroy.

## Gotchas hit in this project

**The stale-lock drill's real error text matched the lock object
exactly.** I killed a real `terraform apply` mid-flight with `kill -9`,
then tried a plan against the same state, and Terraform's own
lock-acquisition error named the same lock id, operation, holder, and
timestamp as the `.tflock` object I had already read directly, confirming
Terraform's error path reads the identical object a human would read by
hand, recorded verbatim in `docs/drills/stale-lock-recovery.md`.

**The killed apply had nothing left to partially apply, and that is a
real limit on what one drill proves.** Dev was already fully converged
before I started the drill, so the process I killed died holding the lock
during its own refresh, never reaching the apply phase. That means this
drill proves the lock survives a kill and the recovery procedure works,
but it does not additionally prove what happens to a resource set that is
genuinely half-created, and I keep that distinct from
`docs/runbooks/terraform-apply-failure.md`'s own separate scope rather
than blurring the two together.

**LocalStack's conditional writes genuinely honored `If-None-Match` under
real contention, which was this phase's one open technical risk.**
RESEARCH.md flagged this as unproven going in, and
`scripts/verify-tfstate-locking.sh` closed it live, not against a single
sequential apply but against a genuinely concurrent second operation that
got refused with the real contention error, so this estate never needed
the DynamoDB fallback that document had left open as an option.

## War stories

The industry failure this control exists for is two engineers running
`terraform apply` against the same state file at the same moment, and the
second write silently clobbering whatever the first one had just
written, corrupting the state in a way that is often only discovered much
later, once Terraform's idea of the world stops matching reality. The
concrete control in this estate that closes that gap is `use_lockfile =
true` in every environment's `backend.tf`, backed by S3's conditional
PUT, and I do not have to take that on faith, `scripts/verify-tfstate-locking.sh`
proves live that a second concurrent operation against the same state
gets refused rather than silently succeeding.

## Command cheat-sheet

```bash
bash scripts/verify-tfstate-locking.sh
aws --endpoint-url http://localhost:4566 s3api head-object \
  --bucket athena-tfstate-dev --key core-network/terraform.tfstate.tflock
terraform force-unlock -force <lock-id>
terraform plan -input=false -detailed-exitcode
```
