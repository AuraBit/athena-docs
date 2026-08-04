# Drill: Image Promotion and Rollback (CD-04, D-30)

**Status:** procedure recorded; live execution DEFERRED to Phase 3
verification (compressed-execution close). The promotion workflow's logic
is statically verified; this drill is the standing exercise that proves the
control end to end, and its first dated run belongs to `/gsd-verify-work 3`.
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
| — | — | pending first execution | scheduled with Phase 3 verify-work |
