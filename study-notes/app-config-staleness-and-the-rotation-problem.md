# App Config Staleness and the Rotation Problem

* Tool: (deliberately) environment variables read once at process start
* Summary: Config read at boot is a snapshot that ages — the media service caches its startup config on purpose, manufacturing the staleness problem Phase 5's secret rotation exists to solve
* Phase introduced: 03-app-ci-cd-walking-skeleton
* Related ADRs: athena-app/docs/adr/0003-media-service-scope-and-deliberate-uninstrumentation.md
* Last reviewed: 2026-08-04

## Mental model

Most services read environment variables once in main(), build their
clients, and never look back. That snapshot model is fine for values that
never change, like a bucket name. It is quietly catastrophic for values
that change on a schedule, like credentials under rotation — the process
keeps authenticating with the credential it read at boot until it dies. My
media service does exactly this, on purpose. It is the estate's controlled
specimen of the staleness disease.

## Common interview questions

**Why build the problem in deliberately?** Because my Phase 5 Vault work
needs a service whose rotation pain is real, owned, and demonstrable.
Retrofitting dynamic secrets onto a service that already handles rotation
would demonstrate nothing. The snapshot-config media service is my before
picture, and the interview story is the delta.

**What are the escape paths from config staleness?** I rank them by
operational cost. Cheapest is restart-on-rotate, a rolling restart
triggered by the rotation itself. Next is an agent sidecar that renders
secrets to files the app re-reads, like Vault Agent templates. Then come
SDK-level dynamic credentials with TTLs the app renews, and finally full
push-based config with in-process reload. Kubernetes adds a wrinkle I
always name — a Secret mounted as env vars never updates a running pod,
while file mounts update eventually.

**When is a restart the RIGHT answer?** More often than my pride admits. If
rotation is scheduled, a rolling restart inside the rotation window costs
zero new code and uses the platform's native health-gated rollout. Its
failure modes are the deploy failure modes I already drill. The
sophisticated answer is knowing what the restart costs — connection
draining, cache warmup — and choosing it when that is cheaper than carrying
live-reload complexity in every service.

**How does GitOps interact with config changes?** Config that lives in git
rolls out through sync like any other change — the pod template hash moves,
pods roll, and every process gets a fresh snapshot. The rotation problem is
specifically about values that must change WITHOUT a git commit, which is
what secrets are. That is why I give them a different delivery system in
Phase 5.

## Gotchas hit in this project

* The media service caches its S3 bucket name, datastore addresses, and
  credentials at boot — a bucket rename today requires a restart, and that
  is the recorded, deliberate limitation.
* Kubernetes env-var Secrets never propagate to running pods — a fact I
  verify people on because file-mount intuition transfers wrongly.

## War stories

**The pod that predated its own feature.** While proving the session gate I
watched a freshly-synced Deployment serve old behaviour — the pod had
started before the new image tag landed and its config snapshot pointed at
the world as it was minutes earlier. The fix was a re-pin and a roll, but I
keep the incident as my cleanest demonstration that a running process is a
snapshot of boot time, not a view of current truth.

## Command cheat-sheet

```bash
kubectl -n dev set env deploy/media --list        # what the pod THINKS its config is
kubectl -n dev rollout restart deploy/media       # the cheapest rotation answer
kubectl -n dev get pod -l app=media -o jsonpath='{.items[0].spec.containers[0].env}'
```
