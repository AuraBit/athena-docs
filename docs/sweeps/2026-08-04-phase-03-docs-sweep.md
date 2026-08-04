# Documentation Sweep Record — Phase 3 close (Plan 03-10)

**Why this file exists.** The Phase 3 threat model (T-03-61) requires the
close-of-phase documentation sweep to be *auditable*: every claim corrected
because it no longer matched the code must be named, so a future reader can
verify the sweep did what it says rather than trusting that it happened.
The four sweep commits landed with single-line subjects naming additions
only; this record closes that gap by enumerating the corrections
explicitly. Future sweeps must name corrections in the commit body itself —
this file is the retroactive record for the Phase 3 sweep, not the pattern.

## Sweep commits

| Repo | Commit | Content |
|------|--------|---------|
| athena-docs | `e1f5766` | ADR 0010, diagram refreshes, 5 study notes, drill + drills index |
| athena-infra | `ecf5e86` | 2 runbooks, LocalStack s3 coverage row |
| athena-app | `25b6d1d` | ADRs 0002–0005 (additions only — no corrections) |
| athena-gitops | `46a19f4` | ADRs 0002–0003 (additions only — no corrections) |

## Corrections made (claims that no longer matched the code)

All corrections are in `e1f5766` (athena-docs) and `ecf5e86` (athena-infra):

1. **`diagrams/ci-cd-topology.md`** — the `APPBUILD`, `GITOPSCOMMIT` and
   `ARGOCD` nodes were labelled `FUTURE Phase 3` and carried the `future`
   class; Phase 3 delivered them, so the labels now describe the live
   pipeline (media-ci lint/migration/build/dual-Trivy-scan/publish, the
   bot's gitops-handoff commit, ArgoCD hub with 3 roots + 9 unit
   Applications) and the `future` class was removed from exactly those
   three nodes.
2. **`diagrams/ci-cd-topology.md` (prose)** — the paragraph stating "the
   promotion path drawn above is marked future/Phase 3 in full … no
   automated gitops-commit step exists yet" was stale after Plan 03-08/03-09;
   it was rewritten to describe the delivered loop (immutable short-SHA
   publish, rendered-manifests check, gated stg/prod promotion, one-revert
   rollback).
3. **`diagrams/estate-architecture.md`** — `APPFUTURE` ("FUTURE Phase 3 -
   Athena workloads") and `PLATARGO` ("FUTURE Phase 3 - ArgoCD") corrected
   to the delivered state (workloads in dev/stg/prod; ArgoCD 3.4.6 hub with
   the app cluster registered); `future` class retained only for
   `PLATOBS`, `PLATVAULT`, `PLATSONAR` (Phases 4–6, genuinely undelivered).
4. **`athena-infra/docs/localstack-service-coverage.md`** — the s3 row
   predated Phase 3's consumers; extended with the media bucket usage so
   the coverage table matches what the code actually exercises.

## False-assurance check

The Phase 3 security review (2026-08-05) spot-checked the swept docs for
claims of controls that do not exist and found none: the drills README
explicitly marks the promotion drill `pending` rather than implying it ran,
and `promotion-gating.md`'s "verified live" claim checks out against the
governance state. No stale claim survived the sweep; the gap was
auditability of the corrections, which this record closes.
