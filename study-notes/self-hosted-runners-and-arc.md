# Self-Hosted Runners and Actions Runner Controller

* Tool: GitHub Actions self-hosted runner (JIT-config, ephemeral)
* Summary: A self-hosted runner is your own machine volunteering to execute other people's code on request — every design decision here bounds that trust
* Phase introduced: 01-local-foundations-repo-governance
* Related ADRs: athena-infra/docs/adr/0005-ephemeral-jit-self-hosted-runner.md,
  athena-infra/docs/adr/0006-ci-06-trust-boundary-amendment.md
* Last reviewed: 2026-08-04

## Mental model

A self-hosted runner is your own machine volunteering to execute other
people's — or your own CI's — code on request. Every design decision about
one is really the same question asked repeatedly: how much do I trust what
gets scheduled onto it, and what happens if that trust turns out to be
misplaced.

## Common interview questions

**Ephemeral vs. persistent runners — why does it matter?** I care about
this because an ephemeral runner registers, runs exactly one job, and then
deregisters, so no job ever inherits a previous job's filesystem state,
credentials, or environment. A persistent runner accumulates state across
jobs indefinitely instead. If a job on that persistent runner is
compromised, or just careless, it can leave something behind for the job
that runs after it to find, whether that was intended or not.

**How do you scope a runner's blast radius?** I scope it with five
separate controls stacked together. First, a dedicated runner group, never
the org's Default group, which I cover under Gotchas. Second, trigger
restrictions bounding exactly which contexts can reach this runner, a
narrower guard than a blanket no-PR rule since Phase 2's trust-boundary
amendment, which I answer fully below. Third, a redundant job-level
branch or repository condition sitting alongside those trigger
restrictions. Fourth, an org-wide action allowlist bounding what can even
execute on the runner. Fifth, the fork-PR-approval gate sitting upstream
of all four of the others. No single one of these five is sufficient by
itself. The actual answer is the whole stack, all five, together.

**When can a pull request reach the self-hosted runner, and doesn't that
reopen the pwn-request risk CI-06 exists for?** A same-repository pull
request can reach it, a fork pull request never can, and I need to
explain why that split is safe rather than just asserting it. The
pwn-request attack is specific to forks, it requires the proposed code to
come from someone who does not already have write access to this
repository. A branch that lives in this same repository can only exist
because someone with write access pushed it here, and that person could
already push straight to `main` and reach this runner immediately, no
pull request, no review, no waiting. So admitting same-repository pull
requests changes when a trusted person's code executes, one pull request
earlier than a bare push to `main`, not who is allowed to make it
execute. Fork pull requests still never reach this runner, the guard is
one boolean, the fork's own repository name never equals this
repository's name, and the organisation-level fork-approval policy stays
in place as a fully separate, independent control on top of it. I name
the residual risk honestly rather than hiding it. A compromised
collaborator account, or a malicious commit from a legitimate
collaborator, now reaches self-hosted execution one step earlier in the
lifecycle than before this amendment. I accept that at this estate's
stated ASVS Level 1 posture, recorded in ADR-0006.

**JIT vs. long-lived registration credentials?** JIT, `generate-jitconfig`,
is what I reach for: it issues a single-use config that lasts roughly one
hour, fetched fresh at every runner start. It uses a narrowly-scoped PAT,
`manage_runners:org` only, that is never the runner's own authentication
credential. A long-lived registration token works differently. Written to
disk the traditional way, with `config.sh --token`, it persists
indefinitely, and if it leaks, it grants ongoing registration ability with
no expiry at all. That is exactly the difference that makes JIT my
default.

**When would you reach for Actions Runner Controller (ARC), and when
not?** I'd reach for ARC at fleet scale, where I need many autoscaling
ephemeral runners behind a queue, provisioned declaratively through a
Kubernetes CRD instead of by hand, machine by machine. I would not reach
for it here, because this estate fixes the runner pool to one specific
local machine running a small, fixed number of instances, not an
autoscaling fleet. There is no fleet to autoscale, so ARC's entire value
proposition just does not apply to this estate's requirement.

**What do runner groups actually buy you?** A runner group buys me a
scoping boundary that's independent of trigger and branch controls
entirely. It answers a different question: which repositories are even
allowed to dispatch a job to this pool at all. Critically, it also decides
whether public repositories may use the pool, and an org's own Default
group ships with that flag off by default, which is exactly why I never
use the Default group here.

**You run more than one runner instance now, how does that change the
blast-radius math?** I run a small pool, two templated systemd units by
default, each independently JIT-registered and ephemeral, so pull-request
plans stay responsive instead of queueing behind an in-flight apply. Each
instance is root-equivalent on this host through its own `docker`-group
membership, the same trust cost I already accept for one instance, so
the number of instances is genuinely the number of concurrent jobs
holding that authority at any moment, not a free multiplier. That is
exactly why I keep the pool deliberately small, two or three instances,
rather than sizing it for throughput the way I would size a real fleet.

## Gotchas hit in this project

**`docker`-group membership is root-equivalent on this host.** Docker's own
security model treats socket access as full root, since a container can be
launched with arbitrary host bind-mounts. This is the accepted cost of
running the runner against the host Docker daemon (rather than
Docker-in-Docker) so BuildKit's layer cache persists across every ephemeral
runner instance — proven live by a `CACHED` build layer on a run that
started from a brand-new runner registration.

**A job-level condition and a trigger restriction are deliberately
redundant, not accidentally duplicated.** A single control eventually gets
edited away by someone who no longer remembers what it was protecting —
this estate's own self-hosted workflow carries both the trigger-list
restriction (no PR-family event declared at all) *and* a redundant
`if: github.ref == 'refs/heads/main'` job condition, each independently and
mechanically asserted on every run rather than trusted to still be there.

## War stories

**Public-repository self-hosted runners are a named, standard compromise
path in the industry** — a fork PR that reaches self-hosted execution
against a repo's secrets and network access is a well-known attack
narrative, not a hypothetical. This estate accepts running one anyway
(there's no alternative that satisfies the $0/local-machine constraint) but
stacks four independent, named compensating controls rather than trusting
any single one: (1) no PR-family trigger on any self-hosted workflow, (2)
the redundant job-level branch condition, (3) the org-level fork-PR-approval
setting, (4) the org-wide action allowlist plus required SHA-pinning. None
of the four alone is sufficient; together they are the honest answer to
"why is it safe to run a self-hosted runner against a public repository on
a personal workstation" — "we accepted a real risk and here are the
controls that bound it," not "the risk doesn't exist."

**ARC — considered and rejected, not dismissed.** ARC is the right tool at
fleet scale: many autoscaling ephemeral runners behind a queue, provisioned
declaratively via a `RunnerScaleSet` CRD, with no systemd unit per machine
to reason about. It was rejected here for two reasons specific to this
estate, not because it's a bad tool in general — the requirement fixes the
runner to exactly one local machine with exactly one concurrent job ever
possible (nothing to autoscale), and moving runner lifecycle into
Kubernetes would strip Ansible of its one scoped, production-shaped role in
this project.

## Command cheat-sheet

```bash
sudo systemctl status athena-runner
gh api orgs/AuraBit/actions/runners --jq '.runners[] | {name, status, busy}'
sudo cat /home/athena-runner/.runner | jq '{Ephemeral: .Ephemeral, AgentId: .AgentId}'
sudo systemctl restart athena-runner
```
