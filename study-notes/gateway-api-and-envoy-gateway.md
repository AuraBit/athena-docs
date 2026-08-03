# Gateway API and Envoy Gateway

* Tool: Gateway API (Envoy Gateway implementation)
* Summary: Role-oriented successor to Ingress — Envoy Gateway is the enterprise-standard data plane chosen over the now-retired ingress-nginx
* Phase introduced: 01-local-foundations-repo-governance
* Related ADRs: athena-infra/docs/adr/0002-envoy-gateway-as-gateway-api-implementation.md
* Last reviewed: 2026-08-03

## Mental model

Gateway API is Kubernetes' role-oriented successor to Ingress: it splits
infrastructure ownership (`GatewayClass` selects the implementation,
`Gateway` owns the listener and TLS termination) from application ownership
(`HTTPRoute` owns routing rules), so a platform team and an app team can
each manage their own objects without colliding. Envoy Gateway is one
*implementation* of that API — a controller that watches those CRDs and
programs the Envoy proxy data plane to match.

## Common interview questions

**What did Ingress get wrong that Gateway API fixes?** Ingress bundled
infrastructure and application concerns into a single object type, with
anything beyond basic host/path routing pushed into vendor-specific
annotations — no standard, portable way to express traffic splitting,
header manipulation, or a clean ownership split. Gateway API expresses all
of that with typed, portable resources and genuine RBAC separation between
who owns the `Gateway` and who owns `HTTPRoute`s.

**Why is ingress-nginx not the answer in 2026?** Its best-effort maintenance
ended March 2026 — no further releases, bugfixes, or CVE patches, ever.
Building new local-routing configuration on a retired controller undermines
a project whose entire value proposition is demonstrating current,
production-grade practice.

**How does traffic splitting work, and why does Phase 4's progressive
delivery depend on it?** An `HTTPRoute`'s `backendRefs` each carry a
`weight`; a conformant Gateway API implementation routes traffic
proportionally across backends by that weight. This is the exact mechanism
Argo Rollouts' canary steps drive under the hood — weighted traffic
splitting between ReplicaSets — which is why the data-plane's Gateway API
conformance quality (not just "does it route") mattered when choosing an
implementation.

**What's the difference between an implementation and the API?** Gateway
API is a spec: a fixed set of CRDs (`GatewayClass`, `Gateway`, `HTTPRoute`,
etc.) and their expected semantics. Envoy Gateway, Traefik, Cilium, and
others are *implementations* — controllers that watch those same CRDs and
translate them into their own proxy's configuration. Same API surface for
the cluster operator regardless of which implementation sits underneath.

## Gotchas hit in this project

**k3s ships no Gateway API CRDs at all.** k3s bundles only its own
ingress-mode Traefik install (disabled in this project) — Gateway API's
CRDs (`GatewayClass`, `Gateway`, `HTTPRoute`, etc.) don't exist on a fresh
k3s cluster until something installs them. Installing the Envoy Gateway
controller before those CRDs exist fails with an unresolvable-kind error
(`no matches for kind "GatewayClass"`).

**Helm v4 Server-Side-Apply vs. a prior client-side-apply CRD install.**
The originally-researched sequence called for a standalone `kubectl apply`
of the Gateway API CRD release before the Envoy Gateway Helm install. Under
Helm v4, the `envoyproxy/gateway-helm` chart's own `crds` subchart installs
Gateway API CRDs via Server-Side Apply as part of `helm install` — and
SSA-installing over a CRD already owned by `kubectl apply`'s client-side-apply
field manager hard-conflicts (`Apply failed with N conflicts`). Fixed by
removing the standalone `kubectl apply` step entirely and letting the
chart's own `crds.enabled=true` default own Gateway API CRD installation in
the same atomic `helm install` as its native CRDs — which also guarantees
the CRD version and the controller version actually match.

## War stories

**ingress-nginx's retirement.** Kubernetes' SIG Network/Security Response
Committee announced ingress-nginx's retirement in November 2025; best-effort
maintenance ended March 2026 — no more releases, no more bugfixes, and
critically, no more CVE patches, ever, for a controller that terminates
untrusted internet traffic. The lesson generalizes well beyond this one
controller: building new configuration on a piece of infrastructure whose
maintenance has already ended means any future vulnerability discovered
against it goes unpatched permanently. This is precisely the trap this
project's own `.claude/CLAUDE.md` "What NOT to Use" table exists to name
explicitly, and it's exactly why Envoy Gateway — not ingress-nginx, and not
even a bundled Traefik left at its ingress-mode default — was the chosen
implementation here.

## Command cheat-sheet

```bash
# CRDs are installed by the chart itself (crds.enabled=true), never a
# standalone `kubectl apply` — see the Gotchas section above.
helm install eg oci://docker.io/envoyproxy/gateway-helm --version v1.5.1 \
  -n envoy-gateway-system --create-namespace
kubectl get gatewayclass
kubectl get gateway athena -o jsonpath='{.status.conditions}'
kubectl get httproute -A
```
