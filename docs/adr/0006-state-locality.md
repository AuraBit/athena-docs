# 0006. State Locality

* Status: accepted
* Date: 2026-08-03
* Deciders: Yahia Tarek (YahiaEng)
* Tier: full-madr

## Context and Problem Statement

The estate has two Terraform stacks with fundamentally different
relationships to the resources they describe: the governance stack
(`athena-infra/governance/`, ADR-0005) manages a real, persistent GitHub
organisation; the AWS-emulation stacks (Phase 2/6, targeting LocalStack)
manage resources that live inside an ephemeral, free-tier LocalStack
process that loses its own internal state on every restart. Both stacks
need a Terraform state backend, and treating them identically would produce
a wrong answer for at least one of them — this decision exists to state
that difference as a principle, not an inconsistency to be smoothed over.

## Decision Drivers

* Terraform state's job is to describe what actually exists — state that
  outlives the resources it describes is drift; state that dies with
  resources that persist is data loss.
* The governance stack's resources (the org, its teams, its repositories)
  are real and persistent — they exist independently of whether this local
  machine is running.
* The AWS-emulation stacks' resources exist only inside a LocalStack
  container process that has no persistence guarantee on the free tier — a
  restart wipes LocalStack's own internal state regardless of what
  Terraform's state file claims.
* A world-rebuild runbook (recovery after a LocalStack restart) is far
  simpler to write and to trust if Terraform state and the resources it
  describes always go away *together* — no possibility of state claiming a
  resource exists that a fresh LocalStack process has never heard of.

## Considered Options

* **One shared state backend for every Terraform stack in the estate**
  (either always-local or always-remote), regardless of what each stack's
  resources actually are.
* **State locality principle: state lives with the durability of the thing
  it describes** — local, git-ignored, backed-up state for the governance
  stack; LocalStack S3-backed state for the AWS-emulation stacks. (Chosen.)

## Decision Outcome

Chosen option: **"State locality principle,"** because a single uniform
backend choice is provably wrong for one of the two stacks no matter which
way it's made uniform: local state for the AWS-emulation stacks would let
Terraform's state file claim resources exist that a fresh LocalStack
process has already forgotten (drift on every restart, discovered only when
an `apply` fails against a config that "should" already be applied);
LocalStack-S3-backed state for the governance stack would put the record of
a real, persistent GitHub org inside the one component in this estate that
is *designed* to be ephemeral — losing track of infrastructure that still
exists the moment LocalStack restarts.

### Consequences

* Good, because the governance stack's local state file, git-ignored and
  backed up outside git, correctly reflects that the org it describes
  outlives every local restart — `terraform plan -detailed-exitcode`
  reports zero changes across restarts, exactly as it should for real,
  unchanged infrastructure.
* Good, because the AWS-emulation stacks' LocalStack-S3 state means a
  restart wipes the Terraform state and the emulated resources it
  describes **together** — a coherent fresh world, never drift between
  "what Terraform thinks exists" and "what's actually running." Recovery
  is a documented world-rebuild runbook (`athena-infra/docs/runbooks/
  world-rebuild.md`), deliberately framed as recurring disaster-recovery
  practice rather than an incident to avoid.
* Good, because this principle generalizes cleanly to any future stack
  this estate adds — the question "where should this stack's state live?"
  always has the same answer: wherever the thing it describes actually
  lives.
* Bad, because it means the estate carries two different state-backend
  configurations to understand and explain, rather than one uniform
  pattern — accepted because the alternative (uniform but wrong for one
  stack) is a correctness bug, not a simplicity win.

## Pros and Cons of the Options

### One shared state backend for every stack (always-local)

* Good, because "state lives in a git-ignored local file, full stop" is
  the simplest possible rule to state and follow.
* Bad, because it is silently wrong for the AWS-emulation stacks: a
  LocalStack restart wipes the emulated resources but leaves local
  Terraform state claiming they still exist, producing drift discovered
  only when a subsequent `apply` unexpectedly tries to recreate or fails
  against resources the state file thinks are already there.

### One shared state backend for every stack (always-remote, LocalStack S3)

* Good, because it is a single, consistent remote-state pattern to
  document and reason about.
* Bad, because it is silently wrong for the governance stack in the
  opposite direction: it would put the record of a real, persistent
  GitHub org inside LocalStack — the one component in this estate
  explicitly designed to be ephemeral — meaning a LocalStack restart could
  lose track of live GitHub infrastructure that still exists, with no
  mechanism to reconcile the loss.

### State locality principle: state matches the durability of what it describes (chosen)

* See Decision Outcome and Consequences above.
