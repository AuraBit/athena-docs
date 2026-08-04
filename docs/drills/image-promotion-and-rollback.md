# Drill: Image Promotion and Rollback (CD-04, D-30)

**Status:** executed live 2026-08-05 (first dated run, Phase 3 security
review / verify-work close) — see the execution record below.
**Purpose:** prove by doing that (1) a rejected promotion leaves nothing
behind, (2) an approved promotion lands as one bot commit ArgoCD syncs, and
(3) rollback is a single revert with no rebuild and no registry interaction.

## The drill

1. **Reject leg.** Dispatch `promote` (target `stg`, unit `media`). Confirm
   the run pauses with the rendered diff in the summary. REJECT it.
   Assert: `git -C estate/athena-gitops status --porcelain` clean,
   `git log` free of promotion commits, stg pin unchanged.
2. **Approve leg.** Dispatch again, approve. Assert: bot-authored commit
   `promote(stg): athena-media <tag> (dev -> stg)`, `media-stg` Synced and
   Healthy, running image equals the promoted tag.
3. **Chain-refusal leg.** Dispatch `prod` BEFORE promoting stg again after
   a new dev tag lands — assert the no-op/chain refusal fires with a clear
   message rather than a confusing failure.
4. **Prod leg.** Promote stg -> prod, approve, same assertions as (2) on
   prod.
5. **Rollback leg (not optional).** `git revert` the prod promotion commit,
   push, and time ArgoCD returning prod to the prior tag. Assert: no image
   was built, no registry tag was written, one commit reverted both pin and
   rendered manifests.

## Record of executions

| Date | Legs run | Result | Notes |
|------|----------|--------|-------|
| 2026-08-05 | 1, 3, 2, 4, 5 (all five; refusal leg run while stg still equalled prod) | PASS | Candidate tag `2f2e650`; prior tag `ede5af6`. Timings (UTC): reject leg dispatched 22:38:30, rejected 22:40:06 — no commit, stg pin unchanged, worktree clean. Chain refusal dispatched 22:40:30 — resolve failed with `nothing to promote — prod already runs stg's tag (ede5af6)`, commit skipped. Approve leg dispatched 22:47:08, paused 22:47:42, approved, bot commit `1f6a7fe promote(stg)…` landed 22:48:14, stg pod rolled 22:48:57 (~75s approval→pod). Prod leg dispatched 22:49:22, approved 22:49:56, bot commit `323ce2f promote(prod)…`, prod pod rolled 22:53:08. Rollback: `git revert 323ce2f` → `26ddcce` (2 files: pin + rendered manifest together) pushed 22:53:32, prod pod back on `ede5af6` at 22:56:15 (2m43s push→pod), registry tag list byte-identical before/after, zero athena-app CI runs triggered — no rebuild, no registry write. |

**Divergences observed (first execution — all fixed in-line, none open):**

1. First stg dispatch (22:36) failed pre-approval: `helm not on PATH` on the
   self-hosted resolve job — the runner toolchain never included
   helm/kustomize and this workflow had never run. Fixed by `ea1846c`
   (pinned, checksum-verified tool bootstrap in the resolve job).
2. First approve leg (22:41) failed post-approval: `ATHENA_CI_BOT_TOKEN`
   was never provisioned as an athena-gitops Actions secret
   (`governance/secrets.tf` asserted presence on athena-app/athena-infra
   only). Secret provisioned by the operator; presence assertion extended
   to athena-gitops.
3. Before any leg could run, self-hosted jobs queued indefinitely: the
   `athena-selfhosted` runner group still granted only athena-infra —
   athena-app and athena-gitops were added live (see
   athena-infra/docs/runbooks/runner-ops.md).
