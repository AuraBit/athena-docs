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

**When do you still reach for Ansible in 2026, and when should you
not?** I still reach for Ansible for anything at the host level,
outside any cluster's reconciliation loop entirely — installing OS
packages, standing up systemd services, wiring wildcard DNS, setting
credential file permissions. I don't reach for it for anything a
cluster can already run declaratively: a Helm chart, a Kustomize
overlay, a cert-manager `Certificate` object, an ArgoCD Application.
Using Ansible for any of those would be a GitOps regression, quietly
re-introducing an imperative path that nobody reconciles, right next
to a declarative one that's supposed to be the single source of truth.

**Idempotency vs. convergence vs. reconciliation — what's the actual
difference?** Idempotency is the smallest of the three: run one task
twice, and the second run leaves the world exactly where the first run
left it. Convergence is bigger: a whole system moving toward a
described end state no matter where it started, which is what a
well-written Ansible playbook gives me the moment I invoke it, and not
one second longer. Reconciliation is bigger again: a controller
watching actual state continuously and driving it back toward desired
state on its own schedule, forever, which is what Kubernetes
controllers and ArgoCD do and Ansible structurally never does. The line
between the last two comes down to whether a human invoked it or a
controller is watching, and Ansible sits firmly on the invoked side.

**Why is a Kubernetes controller not just "Ansible on a timer"?** A
controller isn't polling, it's watching — it holds a live watch on the
API server and reacts to drift immediately, for as long as the cluster
exists. A cron'd Ansible run only reconciles at whatever interval I
schedule it for, and it has no concept of watching at all. Call it a
poll, not a watch, and remember it stops being useful the exact moment
nobody's running it.

**How does immutable infrastructure change the answer?** If a host is
disposable, if I'd rebuild it rather than mutate it, then Ansible's
classic use case, configuration management in place, shrinks even
further — I just rebuild the image or the instance instead of
converging an existing one. This project's one host is the opposite of
disposable: it's the single developer machine everything else runs on.
That's a real part of why Ansible still keeps a scoped, genuine role
here, rather than none at all.

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
