# 0008. Namespaces vs. Clusters for Environments

* Status: accepted
* Date: 2026-08-03
* Deciders: Yahia Tarek (YahiaEng)
* Tier: short-form

## Context

The Athena app needs dev, stg, and prod environments. A real production
estate sometimes runs one cluster per environment for strong isolation, and
sometimes runs namespaces on a shared cluster for lower operational
overhead — both are legitimate patterns, and this project needs to pick one
and state the trade-off honestly.

## Decision

dev, stg, and prod are **namespaces on the single `app` k3d cluster**
(`clusters/app/namespaces.yaml`, labelled `athena.net/environment=<name>`),
not three separate clusters. The `platform` cluster (ArgoCD, observability,
Vault, SonarQube) is the only other cluster in the estate, and it hosts no
environment-scoped workloads at all — see `athena-infra` ADR-0001 for why
two clusters exist in the first place (platform/app split, not an
environment split).

## Consequences

* What this does **not** model, stated explicitly: no control-plane
  isolation between environments (dev, stg, and prod all share one API
  server, one etcd/SQLite datastore, one set of controllers); no
  per-environment node pools (a noisy-neighbor dev workload can compete for
  the same agent-node resources as prod); and a namespace-scoped blast
  radius rather than a cluster-scoped one — a misconfigured
  cluster-wide resource (a bad `ClusterRole`, a broken CNI policy) can
  affect all three environments simultaneously in a way a cluster-per-
  environment split would contain.
* What's gained: a single cluster to operate, one Envoy Gateway install,
  one cert-manager install, one registry connection — proportionally lower
  operational overhead for a $0, single-host project where running three
  additional k3d clusters would cost real host resources without a
  corresponding fidelity gain for this project's actual learning targets
  (GitOps promotion, progressive delivery, observability — none of which
  require cluster-level isolation to demonstrate).
* Kubernetes-native tools that do apply at the namespace level —
  `ResourceQuota`, `NetworkPolicy`, RBAC scoped per namespace — remain
  available and are the correct place to reason about environment
  isolation within this design, and are expected to be used by later
  phases rather than assumed away.
* This is a stated, revisitable scope boundary: if a future phase's
  learning goal specifically becomes control-plane-level multi-tenancy or
  cluster-per-environment operational patterns, this decision would need
  to be reopened, not silently worked around.
