# Self-Hosted Runners and Actions Runner Controller

* Tool: GitHub Actions self-hosted runner (JIT-config, ephemeral)
* Summary: A self-hosted runner is your own machine volunteering to execute other people's code on request — every design decision here bounds that trust
* Phase introduced: 01-local-foundations-repo-governance
* Related ADRs: athena-infra/docs/adr/0005-ephemeral-jit-self-hosted-runner.md
* Last reviewed: 2026-08-03

## Mental model

A self-hosted runner is your own machine volunteering to execute other
people's — or your own CI's — code on request. Every design decision about
one is really the same question asked repeatedly: how much do I trust what
gets scheduled onto it, and what happens if that trust turns out to be
misplaced.

## Common interview questions

**Ephemeral vs. persistent runners — why does it matter?** An ephemeral
runner registers, runs exactly one job, then deregisters — no job inherits
a previous job's filesystem state, credentials, or environment. A
persistent runner accumulates state across jobs indefinitely; a compromised
or merely careless job on it can leave something behind for the *next* job
to find, intentionally or not.

**How do you scope a runner's blast radius?** A dedicated runner group
(never the org's Default group — see Gotchas), trigger restrictions (no
PR-family event reaching it at all), a redundant job-level branch
condition, an org-wide action allowlist bounding what can even execute, and
the fork-PR-approval gate sitting upstream of all of it. No single one of
these is sufficient alone; the actual answer is the stack of all of them.

**JIT vs. long-lived registration credentials?** JIT
(`generate-jitconfig`) issues a single-use, short-lived (~1 hour) config
fetched fresh at every runner start, using a narrowly-scoped PAT
(`manage_runners:org` only) that is never the runner's own authentication
credential. A long-lived registration token, once written to disk the
traditional way (`config.sh --token`), persists indefinitely — if it
leaks, it grants ongoing registration ability with no expiry.

**When would you reach for Actions Runner Controller (ARC), and when
not?** ARC is the right answer at fleet scale: many autoscaling ephemeral
runners behind a queue, provisioned declaratively via a Kubernetes CRD, no
manual per-machine provisioning. It's the wrong answer when the requirement
fixes the runner to one specific local machine with exactly one concurrent
job ever possible — there is no fleet to autoscale, so ARC's entire value
proposition doesn't apply.

**What do runner groups actually buy you?** A scoping boundary independent
of trigger and branch controls — *which repositories are even allowed to
dispatch a job to this pool at all*, and critically, whether public
repositories are permitted to use it, since an org's own Default group
ships that flag off by default.

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
