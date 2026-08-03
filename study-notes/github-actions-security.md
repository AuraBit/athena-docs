# GitHub Actions Security

* Tool: GitHub Actions (org and repo security posture)
* Summary: A workflow is arbitrary code execution triggered by partly-untrusted input — every control here follows directly from treating it that way
* Phase introduced: 01-local-foundations-repo-governance
* Related ADRs: athena-infra/docs/adr/0005-ephemeral-jit-self-hosted-runner.md
* Last reviewed: 2026-08-03

## Mental model

A GitHub Actions workflow is arbitrary code execution triggered by
partly-untrusted input — a push, a pull request from a fork, an issue
comment — and every control this estate configures follows directly from
treating it that way rather than as "just CI config." The controls exist
because the input triggering execution is not fully trusted by default,
not because GitHub Actions is unusually dangerous.

## Common interview questions

**What can the default `GITHUB_TOKEN` do, and why does read-only-by-default
matter?** It's scoped per-repository, per-run, and by default can be given
broad write access — if a workflow step is compromised (a malicious
dependency, a poisoned third-party action) with write-scoped defaults, it
can push commits, approve PRs, or modify releases far beyond what the job
actually needed. This org sets `default_workflow_permissions = read`
organisation-wide, with individual jobs elevating explicitly, per-job, only
for the specific scopes they actually need.

**Why is a version tag not a safe pin?** A mutable tag like `@v4` is a
pointer, not a commit — the action's maintainer (or an attacker who
compromises that maintainer's account) can force-move the tag to point at
different code without your workflow file's reference changing at all. A
full-length commit SHA is immutable; the tag is not.

**What is a pwn-request?** An attack class where a workflow triggered on
`pull_request_target` (or a misconfigured trigger with elevated
permissions/secrets available) checks out and executes a fork PR's own
code with the *base* repository's privileges — the fork author's code runs
with access it should never have, purely because of how the trigger was
wired, not because of any code review failure.

**Why is a workflow approving its own pull request a problem?** It
collapses the entire "someone other than the author reviewed this"
guarantee — a workflow could open a PR and immediately approve it with the
same automated identity, satisfying a required-review rule with zero real
review. GitHub's own "Allow GitHub Actions to create and approve pull
requests" organisation setting exists specifically to make this impossible
by default; this org has it disabled.

**How would you audit a repository's Actions posture in ten minutes?**
Org level: `allowed_actions` mode and allowlist, `default_workflow_permissions`,
`can_approve_pull_request_reviews`, `sha_pinning_required`. Repo level: the
branch ruleset's required status checks, review count, and `bypass_actors`.
Per-workflow: grep for any unpinned (`@vN`, not a 40-character SHA) action
reference, check the top-level `permissions:` block is explicit and
minimal, and check every trigger for `pull_request_target`.

## Gotchas hit in this project

**A required status check whose context doesn't match any real job name
makes the branch permanently unmergeable.** GitHub compares the required
check's declared `context` string against a job's `id` in the actual
workflow YAML — it does not validate at configuration time that a job with
that id exists. A typo or a renamed job silently produces a branch that can
never satisfy its own required check, with no obviously-wrong error at the
point of misconfiguration. This estate's own `verify-governance.sh` reads
the expected check context *live* from each `lint.yml`'s actual job id at
verification time, rather than hardcoding it, specifically to catch this
class of drift before it becomes a permanently-blocked branch.

## War stories

Three, each tied to a control this estate actually configured, not generic
advice:

1. **The `tj-actions` supply-chain compromise** (a widely-used third-party
   action whose mutable tag was compromised to exfiltrate CI secrets) is
   the concrete motivation for this estate's full-SHA pinning of every
   third-party action, plus the org-wide action allowlist
   (`allowed_actions = "selected"`, GitHub-owned + verified-creator +
   explicitly-named third-party actions only) and
   `sha_pinning_required = true` as a second, GitHub-native enforcement
   layer alongside each `lint.yml`'s own SHA-pin grep check.
2. **pwn-request-style fork-PR attacks** are the concrete motivation for
   "require approval for all outside collaborators" on every repository's
   fork-PR workflow trigger — the one control this project confirmed has
   *zero* API surface at all (every plausible REST/GraphQL path probed
   live returned nothing), recorded as a genuine, permanent manual step
   rather than faked as Terraform-managed.
3. **The workflow-token trigger-suppression behaviour** — events raised
   using the default `GITHUB_TOKEN` do not trigger downstream workflow
   runs, GitHub's own built-in anti-recursion measure — is precisely why
   `athena-ci-bot` exists as a distinct machine account with its own PAT
   rather than the pipeline authenticating as its own `GITHUB_TOKEN`: a
   bot-authored commit or PR review triggers the same checks a human's
   would, where a `GITHUB_TOKEN`-authored one silently would not.

## Command cheat-sheet

```bash
gh api orgs/AuraBit/actions/permissions --jq '{allowed_actions, sha_pinning_required}'
gh api orgs/AuraBit/actions/permissions/workflow --jq '{default_workflow_permissions, can_approve_pull_request_reviews}'
gh run list --repo AuraBit/athena-app --limit 5
gh api repos/AuraBit/athena-app/rulesets --jq '.[].name'
```
