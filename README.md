# athena-docs

The **Athena platform handbook** — the fourth repository in the estate,
alongside `athena-app`, `athena-infra`, and `athena-gitops` (interview-prep
project — see below for the full topology story). This repo is the home for:

- **Estate-level ADRs** — decisions that govern the whole platform (topology,
  the trunk-based/folder-per-env promotion model, the AWS-native tech-stack
  choice, state-locality) rather than a single repo. Per-repo decisions live
  in that repo's own `docs/adr/` instead; only the estate-wide ones live here.
- **Architecture diagrams** — the system-level picture of how the two k3d
  clusters, LocalStack, the four repos, and CI/CD fit together.
- **Per-tool interview study notes** (`study-notes/`) — one file per tool in
  the stack (Terraform, ArgoCD, Argo Rollouts, Vault, SonarQube, OPA, Trivy,
  Checkov, Gitleaks, GitHub Actions, Helm, Kustomize...), each following the
  same template: mental model, common interview questions, gotchas actually
  hit in this project, war stories, and a command cheat-sheet.
- **Runbooks and drill logs** — recovery procedures (the world-rebuild
  runbook lives in `athena-infra` since it's infra-specific; estate-wide
  drills land here) and records of incident-simulation practice.

## Why a fourth repo doesn't violate the three-repo topology

The project's stated topology commitment is **three** real GitHub repos —
`athena-app` (service monorepo + CI), `athena-infra` (Terraform), and
`athena-gitops` (ArgoCD-watched manifests) — chosen specifically because
concurrency queues, GitHub Environments + required reviewers, branch
protection, and real ArgoCD pulls cannot be exercised in local simulation and
justify the overhead of real, separate repositories.

`athena-docs` is deliberately different in kind, not an exception to that
rule: it carries **no CI/CD pipeline** and is **not part of the
app -> infra -> gitops delivery loop** — nothing builds, deploys, or
promotes through it. It exists purely as a documentation surface (D-18),
extending what the three delivery repos already need (a place for
estate-wide ADRs and study notes that don't belong inside any single
delivery repo) without adding a fourth delivery path. The three-repo
commitment is about *pipeline* topology; this repo has none.

## Directory map

```
athena-docs/
  docs/adr/       # estate-level ADRs (topology, promotion model, AWS-native, state-locality)
  study-notes/    # one file per tool, interview-prep template
```

## Status

This repository is currently a skeleton — `docs/adr/` and `study-notes/` are
the only structure Plan 04 seeds here. ADR-0001 ("how we record decisions")
and the first study notes land in Plans 07 and 08.
