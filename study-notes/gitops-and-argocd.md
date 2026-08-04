# GitOps and ArgoCD

* Tool: ArgoCD 3.4.6 (hub-and-spoke on the platform cluster)
* Summary: Git is the desired state and a controller continuously reconciles clusters toward it — deployment becomes a reviewed commit, rollback becomes a revert
* Phase introduced: 03-app-ci-cd-walking-skeleton
* Related ADRs: athena-docs/docs/adr/0010-hub-and-spoke-argocd-topology.md, athena-gitops/docs/adr/0003-app-of-apps-granularity-and-sync-policy.md
* Last reviewed: 2026-08-04

## Mental model

ArgoCD is a reconciliation loop, not a deploy button. An Application binds
a git path to a cluster destination, and the controller continuously diffs
live state against that path, converging on every divergence. CI never
touches a cluster in this model — it writes to git, and the controller does
the rest. Push-based CD asks "did my script run?" while GitOps asks "does
the cluster match the repo?" — and the second question stays answered
forever.

## Common interview questions

**Why hub-and-spoke over an ArgoCD per cluster?** I wanted one control
plane to upgrade, secure, and audit — the same reason fleet operators
consolidate. My platform cluster runs the single ArgoCD, and the app
cluster is just a registered remote destination running zero ArgoCD
components, which I assert in a script rather than assume. The trade I
accepted is that the hub becomes a single point of CD failure. The clusters
keep running their last-synced state if the hub dies — only change delivery
pauses.

**What happens when someone kubectl-edits prod directly?** Self-heal
reverts it, and I measured that at one to two seconds in my drift-revert
drill. Manual drift is not an incident I investigate after the fact — it is
a divergence the controller erases. If the change was legitimate, the
correct path was a commit, and I let the revert teach that lesson.

**Why automated sync with prune and self-heal even in prod?** Because I put
prod's protection in the promotion gate — a human approving a rendered diff
before the commit exists — never in a half-applied sync policy. Once a
commit is on main it is the approved desired state. Letting prod drift from
an approved main would manufacture exactly the drift class my estate exists
to prevent.

**How does ArgoCD authenticate to the remote cluster?** I use the
declarative cluster-Secret mechanism carrying a ServiceAccount bearer token
minted on the app cluster. Wiring it taught me two lessons. The registered
server URL must appear in the apiserver certificate's SANs — my k3d load
balancer was a TCP passthrough whose IP was not there, and I hit a live
x509 failure before registering the server node's address instead. And
cross-cluster network reachability is a prerequisite I now prove up front,
never assume.

## Gotchas hit in this project

* The app cluster's serverlb address fails ArgoCD's TLS validation — the
  SAN list only covers the k3s server node's own IP. I register that node
  address and re-derive it on any rebuild.
* `host.k3d.internal` did not resolve in-cluster until I shipped a CoreDNS
  custom override to both clusters — ArgoCD's repo access depended on it.
* The argo-helm chart lags the ArgoCD app release — 3.5.0 GA'd the day I
  installed, but no chart bundled it yet, so I pinned chart 10.2.2.

## War stories

**The two-second revert.** My CD-02 drill deletes a live Deployment in dev
and times ArgoCD's self-heal. The workload was back before my watch loop
completed twice — one to two seconds against a documented default nearer
five. I use that number in interviews because a measured claim beats a
recited default every time.

## Command cheat-sheet

```bash
kubectl -n argocd get applications                        # all 12 apps at a glance
kubectl -n argocd get app media-dev -o jsonpath='{.status.sync.status}'
bash estate/athena-infra/scripts/verify-argocd.sh          # standing CD-01/CD-02 assertions
argocd app sync media-dev                                  # manual sync (break-glass only)
```
