# 0010. Hub-and-Spoke ArgoCD Topology

* Status: accepted
* Date: 2026-08-04
* Deciders: Yahia Tarek (YahiaEng)
* Tier: full-madr

## Context and Problem Statement

Two k3d clusters (platform, app). ArgoCD can run once per cluster
(standalone), or once on the platform cluster managing the app cluster
remotely (hub-and-spoke). Enterprises run both; which does this estate
model, and what must be true for the hub to reach the spoke?

## Considered Options

* **Per-cluster ArgoCD** — rejected: doubles upgrade/RBAC/SSO surface and
   models nothing the estate's interview story needs; fleet operators
   consolidate the control plane.
* **Hub-and-spoke** (chosen): one ArgoCD on the platform cluster; the app
   cluster is a registered remote destination and runs zero ArgoCD
   components (asserted live by verify-argocd.sh).

## Decision

Hub-and-spoke (CD-01/D-32). Registration is the declarative cluster-Secret
mechanism with a ServiceAccount token minted on the app cluster. Two
live-resolved constraints are part of this record: cross-cluster
reachability required joining the clusters' docker networks and fixing
host.k3d.internal in-cluster DNS (CoreDNS custom override); and the
registered server URL must be the k3s server NODE address, not the
serverlb — the load balancer is a TCP passthrough whose IP is absent from
the apiserver's certificate SANs (x509 failure proven live, recorded in
argocd/apps/dev/media.yaml).

## Consequences

* One control plane to secure, upgrade, and explain; "Argo manages Argo"
  from the dev root Application.
* The hub is a single point of CD failure — acceptable here and stated;
  the runbook (argocd-sync-failures.md) covers the operational half.
