# k3d and Local Kubernetes

* Tool: k3d (wrapping k3s)
* Summary: Two simultaneous k3d/k3s clusters stand in for EKS — lightweight, upstream-conformant Kubernetes with a built-in registry and LoadBalancer
* Phase introduced: 01-local-foundations-repo-governance
* Related ADRs: athena-infra/docs/adr/0001-k3d-dual-cluster-shape.md
* Last reviewed: 2026-08-03

## Mental model

k3d wraps k3s — Rancher's lightweight, CNCF-certified Kubernetes distribution
— inside Docker containers, one container per node. k3s trades some
non-essential controllers and its default storage backend (SQLite instead
of etcd) for a materially lighter steady-state footprint, but the
Kubernetes API and controller behaviour it exposes is upstream-conformant,
so `kubectl`/Helm/ArgoCD behaviour observed against it transfers directly
to real EKS knowledge — nothing about *using* the cluster is a simulation.

## Common interview questions

**k3d vs. kind — when does the difference actually matter?** We picked k3d
for both clusters, and I would only reach for kind instead if a phase's
whole learning goal were etcd or control-plane-component internals. k3d
wraps k3s, which swaps the default etcd datastore for SQLite, strips a few
non-essential controllers, and ships its own local registry and LoadBalancer
out of the box, so it runs lighter and needs less setup scripting. kind
stays closer to vanilla upstream Kubernetes at a heavier steady-state cost,
and it gives you neither a first-class registry nor a LoadBalancer without
you wiring one yourself. For what this project is actually testing — GitOps,
CI, observability, scheduling behaviour — that upstream fidelity doesn't buy
us enough to give up k3d's lower footprint, especially running two clusters
at once, continuously, through a whole study session.

**What does k3s strip out, and what does that cost you?** For the questions
this estate actually gets asked, it costs nothing. k3s swaps the default
etcd datastore for SQLite and drops a handful of non-essential controllers
and cloud-provider integrations, and none of that touches scheduling,
GitOps, or CI behaviour. The one place it would actually cost me is if an
interviewer asked specifically about etcd internals or about one of those
exact stripped controllers, and there I would just say so plainly rather
than bluff an answer this cluster can't back up.

**Why are the server nodes tainted here, and what does that mimic?** We
tainted the server nodes ourselves, with `CriticalAddonsOnly=true:NoExecute`,
so every workload we run — smoke tests, ArgoCD, Prometheus, even the Athena
app itself — lands on agent nodes only. That is us mimicking what a real
EKS cluster already enforces structurally. EKS's control plane is invisible
managed infrastructure. You never schedule a workload onto it, and you
never even see it show up as a node.

**What does a multi-node local cluster prove, and what does it not prove?**
It genuinely proves pod scheduling topology — taints landing where we
expect, tolerations letting the right pods through, `kubectl drain` and
PodDisruptionBudget behaviour holding up, topology-spread constraints
spreading pods the way we configured them. What it does not prove is
failure isolation, and I say that plainly rather than let the drill oversell
itself. Every "node" in both clusters is a container sharing this one
host's kernel and this one host's Docker daemon, so there is no equivalent
to a real EC2 worker instance actually going down. Whatever we conclude from
a drill against these clusters, we say it proves scheduling behaviour, not
failure isolation.

## Gotchas hit in this project

**The Traefik-disable-and-taint ordering trap.** k3d's default Traefik
install job doesn't tolerate the `CriticalAddonsOnly` taint, so tainting the
server node without disabling Traefik in the *same* create invocation hangs
cluster creation indefinitely, waiting on a Traefik pod that will never
schedule. Fix: always pass `--disable=traefik` (or the config-file
equivalent) in the same `k3d cluster create` call that adds the taint —
never taint an already-created cluster with Traefik still enabled.

**The Docker-vs-Podman gap.** This host had Podman 6.0.2 but no Docker
daemon; k3d assumes a Docker-compatible API at the standard socket, and
Podman's rootless mode has historically had compatibility gaps for the
specific operations k3d performs (cgroup delegation, inotify limits).
Rather than attempting the documented-as-fragile Podman compatibility path,
Docker was installed fresh from Arch's `extra` repository as the first task
of this phase — a one-command install with no compatibility risk, versus a
workable-but-fragile alternative for a foundations phase everything else
depends on.

## War stories

**The estate's own EKS-supported-version pin.** k3s was pinned to
`v1.35.5-k3s1` after checking that exact Kubernetes minor against AWS EKS's
own standard-support version list at execution time — not defaulted to
whatever k3d's newest bundled image happened to be. This is a recurring
production discipline worth naming directly in an interview: tracking a
version your *target platform* actually supports, rather than the newest
available upstream, is exactly the kind of decision that separates an
operator who thinks about what a cluster will eventually run against from
someone who just grabbed `latest`.

## Command cheat-sheet

```bash
k3d cluster create app --config k3d/app-cluster.yaml
kubectl --context k3d-app get nodes -o wide
kubectl --context k3d-app describe node <name> | grep -A2 Taints
kubectl config use-context k3d-app
k3d cluster stop app && k3d cluster start app
```
