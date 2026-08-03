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

**What did Ingress get wrong that Gateway API fixes?** Ingress crammed
infrastructure ownership and application ownership into one object type,
and that's the actual problem Gateway API fixes. Anything beyond basic
host and path routing had to get pushed into vendor-specific annotations,
so there was no standard, portable way to express traffic splitting or
header manipulation, and no clean line between who owns the ingress and
who owns the routes. We use Gateway API instead because it splits that
ownership for real: typed, portable resources with genuine RBAC
separation between whoever owns the `Gateway` and whoever owns the
`HTTPRoute`s.

**Why is ingress-nginx not the answer in 2026?** We ruled out
ingress-nginx here, and the date is why. Its best-effort maintenance
ended in March 2026, so there are no more releases, no more bug fixes,
and no more CVE patches, ever. I wasn't going to build this project's
local routing on a controller that's already retired, not when the
whole point of this estate is demonstrating current, production-grade
practice.

**How does traffic splitting work, and why does Phase 4's progressive
delivery depend on it?** Each backend listed under an `HTTPRoute`'s
`backendRefs` carries its own weight. A conformant Gateway API
implementation reads those weights and splits traffic across the
backends proportionally, so a `backendRefs` entry weighted three times
higher than another gets three times the traffic. That's the exact
mechanism Argo Rollouts drives under the hood for its canary steps in
Phase 4, shifting weight between ReplicaSets step by step. That's why I
cared about the data plane's Gateway API conformance quality here, not
just whether it could route at all.

**What's the difference between an implementation and the API?** Gateway
API is the spec, not a running thing: a fixed set of CRDs like
`GatewayClass`, `Gateway`, and `HTTPRoute`, plus the semantics those
objects are expected to carry. Envoy Gateway is one controller that
actually implements that spec — it watches those same CRDs and programs
its own proxy to match, the same way Traefik or Cilium would watch the
identical CRDs and program a different proxy. Whichever controller sits
underneath, I see the same API surface as the cluster operator.

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
