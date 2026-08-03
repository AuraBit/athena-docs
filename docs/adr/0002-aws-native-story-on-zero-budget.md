# 0002. AWS-Native Story on a Zero Budget

* Status: accepted
* Date: 2026-08-03
* Deciders: Yahia Tarek (YahiaEng)
* Tier: full-madr

## Context and Problem Statement

The estate needs to tell a coherent cloud story — EKS, Karpenter, S3,
CloudFront, RDS, ElastiCache — while executing entirely on a $0 budget with
no real cloud spend. The tension is direct: production-grade fidelity is a
stated project constraint, and so is strictly local execution. Every
component of the cloud story needs an explicit answer to "is this actually
verified locally, or is it code-and-docs only," because silently blurring
that line would turn this handbook into a source of false interview claims
— the one failure this project's threat model treats as unacceptable.

## Decision Drivers

* Real cloud spend is categorically excluded by the project's $0
  constraint — not a preference, a hard budget floor.
* The target job market (Deloitte/VOIS-tier senior DevOps roles) is
  AWS-native — a GCP or multi-cloud story would be less directly
  transferable to the interviews this project exists to prepare for.
* Local emulation quality varies sharply by service: some AWS services have
  excellent free local emulation (S3, IAM, EC2 metadata via LocalStack);
  others (RDS, ElastiCache, CloudFront, EKS, Karpenter) either require a
  paid LocalStack tier or have no meaningful local stand-in at all.
* The handbook must never let a code+docs-only capability be read as a
  verified one — this is the load-bearing honesty requirement threat T-01-35
  exists to mitigate.

## Considered Options

* **Real cloud spend** — provision the actual AWS services and pay for
  them.
* **Multi-cloud abstraction** (e.g. Crossplane) — abstract over providers
  instead of committing to one.
* **A GCP-native story instead of AWS** — swap the target cloud to whichever
  has the best free local emulation.
* **Local emulation with an honest divergence split: verified where
  LocalStack genuinely emulates, production-grade code + docs where it
  doesn't.** (Chosen.)

## Decision Outcome

Chosen option: **"Local emulation with an honest divergence split,"**
because it is the only option that satisfies the $0 constraint without
abandoning the AWS-native target this project's interview value depends on.
Every AWS-touching Terraform resource carries an explicit, evidence-backed
verification mode — never assumed, always confirmed against a real API call
or an explicit code+docs-only statement. `docs/localstack-service-
coverage.md` in `athena-infra` is the authoritative per-service record: at
Plan 03's execution, `s3`, `iam`, and `ec2` are confirmed genuinely emulated
by a live round trip; `rds`, `elasticache`, `cloudfront`, and `eks` are
confirmed code+docs-only by a real API call returning a license-gated
`InternalFailure` — not assumed from LocalStack's own health endpoint,
which optimistically lists all four as `"available"` regardless of license
tier (the exact fake-success trap this decision's threat model exists to
guard against). Karpenter and real ALBs get the same code+docs-only
treatment by design, since they call real EC2 Fleet/Spot and load-balancer
APIs LocalStack's free tier cannot exercise at the fidelity Karpenter's
actual scheduling logic needs.

### Consequences

* Good, because every later phase inherits a clear, mechanically-checked
  contract (`scripts/verify-localstack.sh` parses the coverage table and
  fails if a row overclaims) instead of a phase-by-phase judgment call.
* Good, because the LocalStack Open-Source Program (free Ultimate tier,
  unlocking genuine RDS/ElastiCache/CloudFront/partial-EKS verification)
  remains available as an upgrade path without requiring any architecture
  change — the coverage table's rows simply flip from code+docs-only to
  emulated if approval lands, and the running app's plain-container
  Postgres/Valkey story is unaffected either way.
* Bad, because Phase 6's Data/Storage and Application/Compute stacks must
  treat four services as genuinely unverified against a live emulator
  unless OSS Program approval lands — a real fidelity gap this project
  chooses to disclose rather than paper over.
* Bad, because CloudFront specifically is expected to stay code+docs-only
  even after OSS Program approval — edge-CDN behaviour has no meaningful
  local stand-in regardless of LocalStack tier, a limit this project
  accepts and states plainly rather than pretending a future upgrade
  solves it.

## Pros and Cons of the Options

### Real cloud spend

* Good, because it would be the only option with zero fidelity gap —
  everything genuinely is what it claims to be.
* Bad, because it violates the $0 constraint outright — this option was
  never actually available given the project's stated budget.

### Multi-cloud abstraction (Crossplane etc.)

* Good, because it would demonstrate provider-agnostic infrastructure
  patterns, a real and growing interview topic.
* Bad, because depth in one cloud beats shallow abstraction across several
  for interview preparation targeting specific AWS-native job
  requirements — this project's stated priority is depth, not breadth.
* Bad, because it dilutes the AWS-native story the target roles actually
  need, adding a second learning curve (the abstraction layer itself)
  without proportional interview value.

### A GCP-native story instead of AWS

* Good, because GCP's free-tier local emulation story is in some respects
  more generous than AWS's LocalStack-gated model.
* Bad, because the target job market's listed services (EKS, S3,
  CloudFront, Karpenter) are AWS-specific — a GCP story would require
  translating every interview answer back to AWS terms, adding friction
  exactly where this project should be removing it.
* Rejected early in project scoping (recorded in `PROJECT.md`'s Key
  Decisions table) — not seriously reconsidered here, included for
  completeness of the alternatives record.

### Local emulation with an honest divergence split (chosen)

* See Decision Outcome and Consequences above.
