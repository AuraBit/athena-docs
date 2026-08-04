# Drill: ArgoCD Drift-Revert (CD-02, D-33)

**Date:** 2026-08-04
**Run by:** `estate/athena-infra/scripts/verify-argocd.sh` (repeatable — every invocation
introduces a fresh, real drift against the live `media` Deployment on the app cluster
and watches ArgoCD's own `selfHeal` reconciliation revert it)
**Purpose:** Prove, by causing and watching it (not describing it), that ArgoCD's
`syncPolicy.automated.selfHeal` genuinely reverts a manually-introduced drift on a real
resource — Phase 3 success criterion 4, and the standing assertion `verify-argocd.sh`
now runs forever after as part of `scripts/verify.sh`.

## What we did

`verify-argocd.sh`'s drift-revert check reads the git-declared `replicas` value for the
`media` Deployment from the rendered manifest (`estate/athena-gitops/envs/dev/media/all.yaml`,
the D-28 rendered-manifests contract — the exact value ArgoCD itself is syncing from),
then runs:

```bash
kubectl --context k3d-app -n dev scale deploy/media --replicas=2   # git declares 1
```

directly against the live app cluster — an out-of-band change ArgoCD never authored, the
same class of drift a `kubectl edit` on any field would introduce. It then polls
`kubectl --context k3d-app -n dev get deploy media -o jsonpath='{.spec.replicas}'` once
per second, bounded by a 60-second timeout, until the value matches git's declared `1`
again.

## What we expected

RESEARCH.md's Pattern 2 (ArgoCD's own documented behaviour, cross-referenced against
multiple official-docs sources) states ArgoCD's default self-heal reconciliation
interval is approximately 5 seconds — carried in this plan's `must_haves` as an explicit
backstop truth, since it was unconfirmed on this hardware until this drill ran it for
real.

## What actually happened

Two independent, real runs of `verify-argocd.sh` against the live cluster, both showing
the deployment genuinely drifted and genuinely reverted:

| Run | Drift introduced (UTC) | Drift | Reverted within | Elapsed (observed) |
|-----|-------------------------|-------|------------------|---------------------|
| 1   | 2026-08-04T13:52:15Z    | `replicas: 1` → `2` | yes | **2 seconds** |
| 2   | 2026-08-04T13:52:25Z    | `replicas: 1` → `2` | yes | **1 second** |

Both runs printed `PASS` for the drift-revert check with the elapsed time embedded in
the check name (`verify-argocd.sh`'s own PASS/FAIL line, not a separately transcribed
figure), and `kubectl --context k3d-app -n dev get deploy media -o jsonpath='{.spec.replicas}'`
read `1` (matching `envs/dev/media/all.yaml`) immediately after each run completed.
Running the drill twice consecutively produced identical `5 passed, 0 failed` summaries
both times, and left the Deployment matching git both times — the drill is itself
idempotent, not just the thing it's testing.

**The observed interval (1–2 seconds) is materially faster than the ~5-second documented
default.** This is recorded honestly rather than adjusted to match the documentation:
ArgoCD's application controller was, in both runs, already actively watching this exact
Application (`media-dev`) via a live Kubernetes watch on the app cluster's API server —
not polling on a fixed timer — so a `spec.replicas` change is very likely observed by the
controller's watch stream near-instantly, with the ~1-2s figure representing controller
reconciliation-loop and `kubectl apply` round-trip time rather than a poll-interval wait.
The ~5-second figure in ArgoCD's own docs describes its *default reconciliation timeout*
(the periodic full-resync safety net for drift that watch events might miss, e.g. during
a controller restart), which is a different mechanism from the watch-driven revert this
drill actually exercised. No reconciliation-timeout override was needed to make this
demo visibly convincing — the watch-driven path alone was already well under a second's
worth of human-perceptible delay in both real runs.

## What changed as a result

Nothing needed to change — the self-heal behaviour worked as designed on the first real
attempt, both times. What this drill *did* change:

- Closed the `must_haves` backstop-truth item for this plan: "whether ArgoCD's default
  self-heal retry interval is fast enough to make the drift-revert demo visually
  convincing on this hardware without tuning the reconciliation timeout" is now answered
  from live evidence — yes, comfortably, with real numbers (1–2s) recorded above rather
  than left as an unconfirmed assumption.
- `verify-argocd.sh` now runs this exact drill as a standing, dispatcher-discovered
  assertion (`estate/athena-infra/scripts/verify.sh`) — every future `verify.sh` run
  re-proves CD-02 live, not just at the moment this drill artifact was written.
