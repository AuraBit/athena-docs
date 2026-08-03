# Ansible in a GitOps World

* Tool: Ansible
* Summary: Configuration management retreated to the host boundary — three scoped roles provision the machine a cluster runs on, nothing inside it
* Phase introduced: 01-local-foundations-repo-governance
* Related ADRs: athena-docs/docs/adr/0009-ansibles-scoped-modern-role.md
* Last reviewed: 2026-08-03

## Mental model

Configuration management didn't disappear in a cloud-native/GitOps stack —
it retreated to the host boundary. Everything above "does a Kubernetes
cluster exist and is Docker running" is declarative and continuously
reconciled instead, by Terraform, Helm, Kustomize, and ArgoCD. Ansible's
remaining job is provisioning the host a cluster runs *on top of*, not
anything the cluster itself can reconcile.

## Common interview questions

**When do you still reach for Ansible in 2026, and when should you not?**
Reach for it for host-level bootstrap that exists outside any cluster's
reconciliation loop — OS packages, systemd services, wildcard DNS
configuration, credential file permissions. Don't reach for it for anything
a cluster can run declaratively (Helm charts, Kustomize overlays,
cert-manager `Certificate` objects, ArgoCD Applications) — using Ansible
there is a GitOps regression, quietly re-introducing an imperative,
non-reconciled path next to a declarative one that's supposed to be the
single source of truth.

**Idempotency vs. convergence vs. reconciliation — what's the actual
difference?** Idempotency is a property of one task: running it twice
produces the same result as running it once. Convergence is a system
moving toward a described end state regardless of its starting point —
what a well-written Ansible playbook approximates *at the moment you run
it*. Reconciliation is a controller continuously and repeatedly driving
actual state toward desired state on its own schedule, watching for drift
indefinitely — this is what Kubernetes controllers and ArgoCD do that
Ansible structurally does not; Ansible only converges when invoked.

**Why is a Kubernetes controller not just "Ansible on a timer"?** A
controller watches actual state continuously via the API server's watch
mechanism and reacts to drift immediately and indefinitely. A cron'd
Ansible run only reconciles at whatever interval you schedule it and has
no concept of watching at all — it's a poll, not a watch, and it stops
being useful the moment nobody's running it.

**How does immutable infrastructure change the answer?** If a host is
disposable and gets replaced rather than mutated, configuration management
in place (Ansible's classic use case) shrinks even further — you'd rebuild
the image or instance rather than converge an existing one. This project's
one host is *not* disposable (it's the single developer machine everything
runs on), which is part of why Ansible still has a real, if scoped, role
here rather than none at all.

## Gotchas hit in this project

**Keeping secrets out of the play recap and the journal.** Every Ansible
task that touches the runner registration PAT's existence uses `no_log:
true` — Ansible's default verbose/diff output would otherwise print task
parameters (including secret content passed as `content:`/`var:`) directly
into the play recap, and into `journalctl` if the playbook ever runs under
a logged systemd/CI context.

**A role that's genuinely idempotent vs. one that merely runs twice without
erroring.** `bootstrap-localstack`'s use of `community.docker.docker_compose_v2`
for the compose-lifecycle task gives an accurate `changed=0` signal on a
second run because the module checks desired state before acting. A naive
`command: docker compose up -d` shell-out would have been functionally
fine but reported `changed` on every single run regardless of whether
anything actually changed — a false idempotency signal that would silently
mask a real drift the moment one did occur.

## War stories

**This estate's own boundary is the concrete illustration of "why doesn't
this project use Ansible for more?".** Exactly three roles exist —
`bootstrap-dns` (dnsmasq wildcard config), `bootstrap-localstack` (the
AWS-emulation host service), and `github-runner` (the self-hosted runner's
systemd unit and JIT-config credential flow) — and nothing runs inside
either Kubernetes cluster through Ansible at all. That's not an incomplete
project; it's the honest, defensible shape of Ansible's role in a
cloud-native estate: everything on the host, outside any cluster's
reconciliation loop, is Ansible's job; everything a cluster can run
declaratively (Gateway API objects, cert-manager `Certificate`s, and
eventually ArgoCD `Application`s) is deliberately *not* an Ansible role,
by design, not because nobody got around to writing more of them.

## Command cheat-sheet

```bash
ansible-playbook estate/athena-infra/ansible/site.yml
ansible-playbook estate/athena-infra/ansible/site.yml --check --diff
ansible-playbook estate/athena-infra/ansible/site.yml --tags localstack
ansible-playbook estate/athena-infra/ansible/site.yml -vvv
```
