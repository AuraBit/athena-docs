# 0007. No Service Mesh

* Status: accepted
* Date: 2026-08-03
* Deciders: Yahia Tarek (YahiaEng)
* Tier: short-form

## Context

Progressive delivery (canary and blue-green rollouts with automated
analysis) needs traffic-shifting capability. A service mesh (Istio,
Linkerd) is the traditional way to get fine-grained weighted traffic
splitting, mTLS everywhere, and free L7 telemetry — but it's also a large
additional operational surface (a control plane, sidecar injection, its own
failure modes) for a project already running Argo Rollouts, Envoy Gateway,
and two Kubernetes clusters.

## Decision

No service mesh is deployed. Argo Rollouts (Phase 4) performs canary and
blue-green traffic shifting directly against Envoy Gateway's Gateway API
resources (`HTTPRoute` weight adjustments), which is sufficient for this
project's progressive-delivery story without a mesh's control plane and
sidecar-injection surface. This was a project-level scoping decision
(recorded in `PROJECT.md`'s Out of Scope table) — this ADR is where the
reasoning and the honest cost are written down for the interview
conversation.

## Consequences

* What's gained: one fewer control plane to operate, secure, and debug;
  Argo Rollouts + Gateway API is a proven, lighter-weight combination for
  exactly this project's canary/blue-green requirement.
* What's lost, stated plainly rather than glossed over: automatic mTLS
  between every service (this estate's inter-service traffic is
  unencrypted at the mesh layer — a real gap against a production system
  that would run a mesh specifically for this), and the free, per-request
  L7 telemetry a mesh's sidecars would otherwise produce without any
  application instrumentation.
* Envoy Gateway (ADR-0002, chosen as the Gateway API implementation for
  unrelated reasons — L7 routing, TLS, Rollouts conformance) partially
  recovers the mesh-adjacent interview surface: Envoy is the same data
  plane technology many meshes are built on, so this project can still
  speak concretely to Envoy's proxy model even without running it in mesh
  mode.
* If a future phase's learning goal specifically becomes mTLS or per-
  request mesh telemetry, this decision would need to be revisited — it is
  a deliberate scope boundary for this milestone, not a permanent
  architectural rejection of meshes in general.
