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

**k3d vs. kind — when does the difference actually matter?** k3d wraps k3s
(SQLite instead of etcd by default, some controllers stripped, a lighter
footprint, and a built-in local registry + LoadBalancer); kind is closer to
vanilla upstream Kubernetes at a heavier steady-state cost, with no
first-class registry or LoadBalancer of its own. The difference matters
specifically when a phase's learning goal is etcd or control-plane-component
internals — fall back to kind for that one cluster in that case. For this
project's actual focus (GitOps, CI, observability, scheduling behaviour) it
doesn't matter enough to give up k3d's lower footprint, especially since two
clusters run simultaneously and continuously during study sessions.

**What does k3s strip out, and what does that cost you?** An alternate
default storage backend (SQLite, not etcd) and some non-essential
controllers/cloud-provider integrations. Irrelevant to scheduling, GitOps,
or CI questions; a real gap only if the interview question is specifically
about etcd internals or a specific stripped controller.

**Why are the server nodes tainted here, and what does that mimic?**
`CriticalAddonsOnly=true:NoExecute` forces every workload — smoke tests,
ArgoCD, Prometheus, the Athena app itself — onto agent nodes only, the same
scheduling discipline a real EKS cluster enforces structurally: EKS's
control plane is invisible managed infrastructure you never schedule
workloads onto and never even see as a node.

**What does a multi-node local cluster prove, and what does it not prove?**
It faithfully proves pod scheduling topology: taints, tolerations, node
counts, `kubectl drain` and PodDisruptionBudget behaviour, topology-spread
constraints. It does **not** prove failure isolation — every "node" in
both clusters is a container sharing this one host's kernel and Docker
daemon; there is no equivalent to a real EC2 worker instance going down.
Any answer derived from a drill against these clusters has to say "this
proves scheduling behaviour, not failure isolation."

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
