# athena-docs

The **Athena platform handbook** — the fourth repository in the estate,
alongside `athena-app`, `athena-infra`, and `athena-gitops` (interview-prep
project — see [Why a fourth repo doesn't violate the three-repo
topology](#why-a-fourth-repo-doesnt-violate-the-three-repo-topology) below
for the full story). This repo is the home for:

- **Estate-level ADRs** ([`docs/adr/`](docs/adr/)) — decisions that govern
  the whole platform (topology, the trunk-based/folder-per-env promotion
  model, the AWS-native tech-stack choice, state locality) rather than a
  single repo. Per-repo decisions live in that repo's own `docs/adr/`
  instead; only estate-wide ones live here. Start at
  [ADR-0001](docs/adr/0001-how-we-record-decisions.md) for the rules every
  ADR in this estate follows, and see the generated
  [**master ADR index**](docs/adr/README.md) for every ADR across all four
  repositories.
- **Architecture diagrams** ([`diagrams/`](diagrams/)) — the system-level
  picture of how the two k3d clusters, LocalStack, the registry, DNS/TLS,
  and the GitHub organisation fit together
  ([`diagrams/estate-architecture.md`](diagrams/estate-architecture.md)),
  and the CI/CD control-flow and trust-boundary picture
  ([`diagrams/ci-cd-topology.md`](diagrams/ci-cd-topology.md)).
- **Per-tool interview study notes** (`study-notes/`) — one file per tool in
  the stack, each following the same five-section
  [template](study-notes/_template.md): mental model, common interview
  questions, gotchas actually hit in this project, war stories, and a
  command cheat-sheet. The index is script-generated the same way the ADR
  index is — see the generated
  [**study-notes index**](study-notes/README.md).
- **Runbooks and drill logs** — recovery procedures (the world-rebuild
  runbook lives in `athena-infra` since it's infra-specific; estate-wide
  drills land here) and records of incident-simulation practice.

## Why a fourth repo doesn't violate the three-repo topology

The project's stated topology commitment is **three** real GitHub repos —
`athena-app` (service monorepo + CI), `athena-infra` (Terraform), and
`athena-gitops` (ArgoCD-watched manifests) — chosen specifically because
concurrency queues, GitHub Environments + required reviewers, branch
protection, and real ArgoCD pulls cannot be exercised in local simulation and
justify the overhead of real, separate repositories. See
[`athena-docs` ADR-0003](docs/adr/0003-repository-topology.md) for the full
decision record.

`athena-docs` is deliberately different in kind, not an exception to that
rule: it carries **no CI/CD pipeline** and is **not part of the
app -> infra -> gitops delivery loop** — nothing builds, deploys, or
promotes through it. It exists purely as a documentation surface, extending
what the three delivery repos already need (a place for estate-wide ADRs
and study notes that don't belong inside any single delivery repo) without
adding a fourth delivery path. The three-repo commitment is about *pipeline*
topology; this repo has none.

## Directory map

```
athena-docs/
  docs/adr/       # estate-level ADRs (topology, promotion model, AWS-native, state-locality)
                   # + docs/adr/README.md, the generated master index across all four repos
  diagrams/       # estate-architecture.md and ci-cd-topology.md, Mermaid-in-markdown
  study-notes/    # one file per tool, interview-prep template (Plan 08)
  scripts/        # gen-adr-index.sh, check-adr-hygiene.sh (this repo's own tooling)
```

## How to add an ADR

1. Decide which tier the decision warrants — read
   [ADR-0001](docs/adr/0001-how-we-record-decisions.md)'s tier-selection
   rule first. When genuinely unsure, prefer the full tier: the cost of an
   unnecessary Considered Options section is small next to the cost of a
   missing one.
2. Decide which repo the ADR belongs in — this repo (`athena-docs`) for
   estate-level decisions, or the repository the decision governs for
   everything else, so the ADR and the code it explains can change in the
   same pull request.
3. Find the next number for that repo's `docs/adr/` (per-repository
   sequential numbering — two repos both having an ADR `0001` is correct).
4. Write the file as `NNNN-kebab-case-slug.md`, following ADR-0001's header
   fields (`Status`, `Date`, `Deciders`, `Tier`) and section order for the
   tier you chose.
5. From this repo, run `bash scripts/gen-adr-index.sh` to regenerate
   [`docs/adr/README.md`](docs/adr/README.md) — never hand-edit that file.
6. Run `bash scripts/check-adr-hygiene.sh` before committing: it catches
   numeric-prefix collisions, filename-convention violations, a full-tier
   claim without a real Considered Options section, and a stale index.

## Status

This repository moved past skeleton with Plan 07: `docs/adr/` now carries
nine estate-level ADRs plus the generated master index spanning all four
repos, and `diagrams/` carries the estate-architecture and CI/CD-topology
pictures. Plan 08 filled out `study-notes/`: ten notes covering every tool
Phase 1 introduced, in one enforced format, with a generated and
mechanically-hygiene-checked index of their own.
