# act and the CI Inner Loop

* Tool: act (nektos/act)
* Summary: A fast local approximation of a workflow's own shell logic — never a second implementation of GitHub Actions' scheduling and service layer
* Phase introduced: 01-local-foundations-repo-governance
* Related ADRs: athena-infra/docs/adr/0005-ephemeral-jit-self-hosted-runner.md
* Last reviewed: 2026-08-03

## Mental model

`act` runs a workflow's steps inside containers on your own machine, using
a Docker image chosen to approximate a GitHub-hosted runner image — it is a
fast local approximation of the job's own shell logic, not a second
implementation of GitHub Actions' scheduling, queueing, or service-side
behaviour.

## Common interview questions

**What can a local runner prove, and what can't it?** It proves the
workflow file parses, jobs and steps execute in the declared order, and
each step's own shell logic runs correctly. It cannot prove anything that
depends on GitHub's own service-side behaviour: Environment approval
gating, concurrency-group queuing, merge-queue ordering, which physical
runner a job actually lands on, or org-level Actions policy enforcement.

**How do you shorten a CI feedback loop generally, beyond "run it
faster"?** Fail fast on the parts that are genuinely reproducible locally
— syntax, shell logic, unit tests — before ever pushing. Treat anything
that depends on service-side state as something only a real push can
verify, and don't try to fake that locally; the actual skill is correctly
triaging which class a given check belongs to, not making everything
local by force.

**What would you still verify against a real push?** Everything on the
"what act does not prove" list: Environment required-reviewer gating,
concurrency-group serialization, merge-queue behaviour, the exact runner
label routing, and org-wide Actions policy enforcement (allowlist,
SHA-pin requirement, default token permissions).

## Gotchas hit in this project

**`act` runs every job in one shared Docker network namespace regardless of
the declared `runs-on:` labels.** It never distinguishes `self-hosted` from
`ubuntu-latest` the way GitHub's real scheduler routes jobs to genuinely
different machines — a green `act` run says nothing about whether a job
would actually land on this project's own self-hosted runner specifically.

**The mandated medium-tier image doesn't ship `ruby`, which one of this
estate's own lint checks depends on.** `catthehacker/ubuntu:act-latest`
(the medium tier, this project's explicit, deliberate size-tradeoff choice
per `.claude/CLAUDE.md`) does not ship `ruby` — real GitHub-hosted
`ubuntu-latest` runners ship it as standard tooling; act's medium tier
deliberately doesn't, since a smaller image is the entire point of
choosing medium over the ~18GB large tier. Fixed by layering a minimal
local image (the stock medium tier plus `ruby`, ~40MB heavier) rather than
either abandoning the medium-tier decision or editing the workflow that
needed it.

## War stories

**False confidence from a passing local run is the same failure class as
LocalStack's fake-success trap** — worth naming as the *same class* rather
than as two unrelated coincidences. Both are instances of "the tool reports
success or health while the thing you actually care about (a real gating
behaviour, a real emulated service call) never happened underneath it."
Recognising that a single failure class recurs across two completely
unrelated tools (a local CI runner and a local AWS emulator) is a stronger
interview answer than either instance in isolation, because it demonstrates
the pattern generalises rather than being tool-specific trivia to memorise.

## Command cheat-sheet

```bash
act -l -W .github/workflows/lint.yml
act push -W .github/workflows/lint.yml
act push -W .github/workflows/lint.yml -P ubuntu-latest=athena/act-ubuntu-latest:act-latest --pull=false
act -n -W .github/workflows/lint.yml   # dry-run
```
