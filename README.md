<p align="center">
  <img src="docs/assets/athena-logo.svg" alt="Athena logo" width="130">
</p>

<h1 align="center">athena-docs</h1>

<p align="center">
  The platform handbook for the <a href="https://github.com/AuraBit">Athena estate</a> — where every architecture decision, diagram, and hard-won lesson gets written down.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/ADRs-9%20estate--level-4f46e5" alt="9 estate-level ADRs">
  <img src="https://img.shields.io/badge/study%20notes-10%20tools-7c3aed" alt="10 study notes">
</p>

---

Athena is an open replica of the CI/CD pipeline and infrastructure estate
that large engineering organisations run in production, built to be studied,
broken, fixed, and explained. This repo is where the *explained* part lives.
If you want to understand why the estate looks the way it does — or borrow
its reasoning for your own platform — start here.

## What's inside

- **Estate-level ADRs** ([`docs/adr/`](docs/adr/)) — decisions that govern
  the whole platform: repository topology, the trunk-based
  folder-per-environment promotion model, the AWS-native stack choice on a
  zero budget, Terraform state locality, why there's no service mesh.
  Per-repo decisions live in each repo's own `docs/adr/`; only estate-wide
  ones live here. [ADR-0001](docs/adr/0001-how-we-record-decisions.md) sets
  the rules every ADR follows, and the generated
  [master index](docs/adr/README.md) covers every ADR across all four
  repositories.
- **Architecture diagrams** ([`diagrams/`](diagrams/)) — how the two k3d
  clusters, LocalStack, the registry, DNS/TLS, and the GitHub organisation
  fit together ([`estate-architecture.md`](diagrams/estate-architecture.md)),
  plus the CI/CD control-flow and trust-boundary picture
  ([`ci-cd-topology.md`](diagrams/ci-cd-topology.md)). Mermaid in markdown,
  rendered by GitHub directly.
- **Per-tool study notes** ([`study-notes/`](study-notes/)) — one file per
  tool in the stack, each following the same five-section
  [template](study-notes/_template.md): mental model, common interview
  questions, gotchas actually hit in this project, war stories, and a
  command cheat-sheet. Ten notes so far, from k3d to GitHub Actions
  security; the [index](study-notes/README.md) is script-generated. If
  you're preparing for a senior DevOps or platform interview, this
  directory is the distilled version of everything the estate teaches.
- **Scripts** ([`scripts/`](scripts/)) — the generators and hygiene checks
  that keep the two indexes honest. Both indexes are generated, never
  hand-edited, and CI-checkable freshness is part of the contract.

## Why a fourth repo doesn't violate the three-repo topology

The estate's stated topology commitment is **three** real GitHub repos —
`athena-app` (service monorepo + CI), `athena-infra` (Terraform, clusters,
bootstrap), and `athena-gitops` (ArgoCD-watched manifests) — chosen because
concurrency queues, GitHub Environments with required reviewers, branch
protection, and real ArgoCD pulls cannot be exercised in local simulation.
See [ADR-0003](docs/adr/0003-repository-topology.md) for the decision record.

`athena-docs` is different in kind, not an exception to that rule: it
carries **no CI/CD pipeline** and is **not part of the
app → infra → gitops delivery loop** — nothing builds, deploys, or promotes
through it. The three-repo commitment is about *pipeline* topology; this
repo has none.

## Adding an ADR

1. Decide which tier the decision warrants — read
   [ADR-0001](docs/adr/0001-how-we-record-decisions.md)'s tier-selection
   rule first. When genuinely unsure, prefer the full tier: the cost of an
   unnecessary Considered Options section is small next to the cost of a
   missing one.
2. Decide which repo the ADR belongs in — this repo for estate-level
   decisions, or the repository the decision governs for everything else,
   so the ADR and the code it explains can change in the same pull request.
3. Find the next number for that repo's `docs/adr/` (numbering is
   per-repository — two repos both having an ADR `0001` is correct).
4. Write the file as `NNNN-kebab-case-slug.md`, following ADR-0001's header
   fields (`Status`, `Date`, `Deciders`, `Tier`) and section order.
5. Run `bash scripts/gen-adr-index.sh` to regenerate the
   [master index](docs/adr/README.md) — never hand-edit that file.
6. Run `bash scripts/check-adr-hygiene.sh` before committing: it catches
   numbering collisions, filename-convention violations, a full-tier claim
   without a real Considered Options section, and a stale index.

## License

[MIT](LICENSE)
