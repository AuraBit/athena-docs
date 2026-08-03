# 0001. How We Record Decisions

* Status: accepted
* Date: 2026-08-03
* Deciders: Yahia Tarek (YahiaEng)
* Tier: full-madr

## Context and Problem Statement

This estate's entire reason for existing is interview preparation: the
working code is the proof, but the *why* behind every non-obvious choice is
what actually gets asked about in a senior DevOps interview ("why did you do
it that way, and what did you reject?"). Without a deliberate convention for
recording decisions, that reasoning lives only in the executor's own memory
at the moment a plan runs and evaporates the moment the phase closes —
exactly the failure mode this handbook exists to prevent.

We need a decision-record format and a filing convention that: (1) captures
real rejected alternatives, not just the chosen outcome, because a
rejected-alternatives list *is* the pre-written interview answer; (2) scales
across four repositories without needing a single global sequence or a
central gatekeeper; (3) lets an ADR be updated in the same pull request as
the code it explains, rather than requiring a second PR against a
documentation repo days later; and (4) doesn't demand a full "Considered
Options" essay for a decision so minor that enumerating alternatives would
be theatre (e.g. "we named the field `env` not `environment`").

## Decision Drivers

* An ADR without a genuine rejected-alternatives section has thrown away
  most of its interview value — the format must make that section mandatory
  somewhere, not optional everywhere.
* Decisions that govern exactly one repository should live where the code
  they explain lives, so a future change to that decision updates ADR and
  code atomically in one PR — not scattered across a docs repo that drifts
  out of sync with the code.
* Decisions that govern the whole estate (topology, promotion model,
  cloud story) don't belong inside any single delivery repo, because no
  single repo's PR history is the right place to explain a choice that
  shapes all four repos.
* Every ADR in this estate must demand exactly as much ceremony as its
  actual stakes warrant — forcing full MADR ceremony on "we used `kebab-case`
  for slugs" would train authors to skip ADRs altogether for genuinely minor
  calls, which is worse than a lightweight sanctioned alternative.
* The master index across four repositories must never silently drift from
  what actually exists — a hand-maintained index is a document that lies the
  moment someone forgets to update it.

## Considered Options

* **Full MADR for every decision, no tiering.** One format, no judgment call
  about which tier to use.
* **A single flat "decisions.md" changelog per repo instead of one file per
  ADR.** No numbering scheme to maintain, no per-decision file overhead.
* **A single global ADR sequence across all four repositories, filed
  centrally in `athena-docs` only.** One number space, one home, easy to
  browse.
* **MADR, two-tier: full MADR (with Considered Options) for significant
  decisions, a sanctioned short form (Context, Decision, Consequences) for
  minor ones — numbered per-repository, filed in the repository the decision
  governs, with estate-level decisions filed in `athena-docs`, and a
  generated master index linking all of them.** (Chosen.)

## Decision Outcome

Chosen option: **"MADR, two-tier, per-repository numbering with a generated
master index,"** because it is the only option that satisfies every decision
driver above simultaneously: it keeps the mandatory rejected-alternatives
section for decisions that actually warrant it, it keeps repo-scoped ADRs
co-located with the code they govern so both change in the same PR, it gives
estate-level decisions an unambiguous home, and the generated index closes
the "does this ADR actually exist and is it current" trust gap that a
hand-maintained index cannot.

### Tier-selection rule

Use the **full tier** — Context and Problem Statement, Decision Drivers,
Considered Options (at least two real options, each with a reason it was
rejected), Decision Outcome with its consequences, and Pros and Cons of the
Options — for any decision that meets at least one of these tests:

1. **Costly or one-way to reverse** (e.g. the GitHub org identity, the
   trunk-based/folder-per-environment promotion model).
2. **Shapes more than one repository** (e.g. the AWS-native-on-zero-budget
   story, the four-repository topology itself).
3. **A competent interviewer would ask "why did you do it that way?" about
   it** — this is deliberately the loosest test and the one that should
   dominate judgment calls, because the whole point of this handbook is
   surviving that exact question.

Use the **short form** — Context, Decision, Consequences only — for
genuinely minor decisions where a Considered Options section would be
theatre: naming conventions, which of two structurally-equivalent options
was picked when neither carries real risk, or a decision so narrow that "we
tried the other thing and it obviously didn't work" is the entire honest
story.

Every ADR declares its tier explicitly in a `Tier:` header field
(`full-madr` or `short-form`) so the claim is machine-checkable, not
self-reported prose a reader has to infer. `scripts/check-adr-hygiene.sh`
enforces that any ADR claiming `full-madr` actually contains a `##
Considered Options` section listing at least two options — a full-tier claim
without one is exactly the failure this ADR exists to prevent, and it is
mechanically caught, not just discouraged.

### Numbering and filing

* **Numbering is per-repository, sequential, starting at `0001`.** Two
  different repositories both having an ADR `0001` is correct, not a
  collision — `athena-infra`'s ADR-0001 and `athena-app`'s ADR-0001 are
  unrelated decisions in unrelated numbering spaces.
* **File names are the zero-padded four-digit number, a hyphen, then a
  kebab-case slug of the title** (e.g. `0001-how-we-record-decisions.md`).
* **Estate-level decisions** — topology, the promotion model, the
  AWS-native-on-zero-budget cloud story, cross-cutting principles like
  state locality — live in `athena-docs/docs/adr/`.
* **Repo-scoped decisions** — anything that governs exactly one repository's
  implementation — live in that repository's own `docs/adr/`, so the ADR
  and the code it explains can be changed in the same pull request.
* **Superseding** is done by writing a new ADR that references the old one
  by number and states the reason, then flipping the old ADR's `Status` to
  `superseded by 000N` — never by editing history. An ADR is a historical
  record of what was decided and why at the time; the record of *changing
  your mind* is itself interview material and must not be silently erased.
* **The master index in `athena-docs/docs/adr/README.md` is generated,
  never hand-maintained.** `scripts/gen-adr-index.sh` walks all four
  repositories' `docs/adr/` directories (resolving sibling repositories
  relative to `athena-docs`'s own location on disk) and regenerates the
  index deterministically — no timestamp, no hostname, no directory-order
  dependence, so running it twice in a row produces byte-identical output.
  A repository with zero ADRs still gets a visible section in the index
  (an explicit "no ADRs yet" row), because a silently-omitted section is
  indistinguishable from a section nobody checked.

### Consequences

* Good, because a full-tier ADR is now a mechanically-verified interview
  answer, not an aspiration — `check-adr-hygiene.sh` fails the build if the
  claim and the content diverge.
* Good, because repo-scoped ADRs travel with the code they explain; a
  Terraform module and the ADR justifying its shape can be reviewed and
  merged together.
* Good, because the master index can never silently go stale without a
  human noticing — `check-adr-hygiene.sh`'s freshness check fails loudly.
* Bad, because per-repository numbering means "ADR-0001" is ambiguous
  without a repository qualifier in conversation — mitigated by always
  citing ADRs as `<repo>#000N` in prose and by the generated index always
  grouping by repository.
* Bad, because a two-tier system requires a judgment call on every new
  decision (which tier does this warrant?) — mitigated by the three-part
  test above and by erring toward full tier whenever genuinely unsure, since
  the cost of an unnecessary Considered Options section is small compared to
  the cost of a missing one.

## Pros and Cons of the Options

### Full MADR for every decision, no tiering

* Good, because there is no judgment call to get wrong.
* Good, because every decision automatically gets a rejected-alternatives
  section.
* Bad, because it trains authors to skip ADRs entirely for minor decisions
  rather than pad out a fake "Considered Options" section for a choice that
  had no real alternative — the opposite of the goal.
* Bad, because it wastes reviewer time on ceremony for decisions nobody will
  ever ask "why did you do it that way?" about.

### A single flat "decisions.md" changelog per repo

* Good, because there's no numbering scheme or per-file overhead to
  maintain.
* Bad, because a growing flat file has no stable per-decision address to
  link to from code comments, PR descriptions, or study notes.
* Bad, because it can't be superseded cleanly — you either edit history
  (violates the "never edit history" principle) or the changelog grows
  linearly with no way to mark an old entry dead.
* Bad, because it doesn't scale to a generated cross-repository index the
  way discrete numbered files do — you'd need to parse prose sections
  instead of walking a directory of well-formed files.

### A single global ADR sequence, filed centrally in `athena-docs` only

* Good, because there's exactly one place to look and one number space —
  simplest possible mental model.
* Bad, because it decouples every repo-scoped decision from the code it
  governs — updating a Terraform module's shape and its ADR would require
  two separate PRs in two separate repositories, which will drift.
* Bad, because a single number space across four independently-evolving
  repositories requires a coordination point (who claims the next number?)
  that doesn't exist in this estate's decentralized-repo topology.

### MADR, two-tier, per-repository numbering with a generated master index (chosen)

* Good, because it satisfies every decision driver above (see Decision
  Outcome).
* Good, because it matches how a real multi-repo platform team actually
  organizes decision records — this is itself an accurate interview
  answer to "how do you manage ADRs across a polyrepo estate?"
* Bad, because it's the most mechanically complex option (a generator
  script, a hygiene checker, a tier-selection rule to remember) — accepted
  because the complexity is a one-time cost paid by this ADR and its
  tooling, not a recurring cost paid by every future ADR author.
