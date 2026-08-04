# Drills

Operational exercises this estate runs against LIVE infrastructure — never
described, always performed, always dated. A drill that has never been
executed is recorded as `pending` in its own execution table rather than
implied to work; the estate's discipline is that an unexercised rollback is
a rollback that does not work.

| Drill | Proves | Requirement | First executed |
|-------|--------|-------------|----------------|
| [argocd-drift-revert](argocd-drift-revert.md) | selfHeal reverts real manual drift (measured 1–2s) | CD-02 | 2026-08-04 |
| [image-promotion-and-rollback](image-promotion-and-rollback.md) | gated promotion + one-revert rollback | CD-04/D-30 | executed 2026-08-05, all five legs PASS |

Drill records live here in athena-docs; the operational how-to they
exercise lives in `athena-infra/docs/runbooks/`.
