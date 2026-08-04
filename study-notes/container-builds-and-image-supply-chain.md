# Container Builds and the Image Supply Chain

* Tool: Docker BuildKit + local registry + Trivy + immutable tagging
* Summary: The artifact that runs must be the artifact that was scanned — a chain of custody from build to pod, enforced at every link
* Phase introduced: 03-app-ci-cd-walking-skeleton
* Related ADRs: athena-app/docs/adr/0004-registry-backed-buildkit-cache-on-self-hosted-runners.md, athena-app/docs/adr/0005-image-scanning-threshold-and-the-exception-register.md
* Last reviewed: 2026-08-04

## Mental model

A supply chain is only as strong as its weakest handoff, so every link gets
an explicit mechanism. Build produces an image and hands the byte-identical
artifact to scan via docker-save, never a same-tag rebuild. Scan gates on
fixable HIGH and CRITICAL findings. Publish runs only on default-branch
merges, refuses to overwrite an existing tag, and pushes the exact artifact
scan examined. The handoff then commits that tag to gitops. Every image in
the registry traces to a main-branch commit by construction.

## Common interview questions

**Why immutable short-SHA tags and never latest?** A mutable tag lets the
scan result, the git history, and the running pod refer to three different
images while every dashboard stays green. My publish job enforces
immutability rather than intending it — it queries the registry's tag list
first and fails on collision. My rollbacks never rebuild, they re-pin to a
tag that already exists.

**Why does the scan run twice in one job?** Because I need two different
jobs out of one scanner. I run an all-severities SARIF invocation feeding
the repo's security surface, and a separate blocking invocation restricted
to HIGH and CRITICAL with ignore-unfixed. I split them because the action's
severity filter interacts unreliably with the reporting format — I
confirmed the upstream issues were still open before pinning. The
vulnerability database is cached, so the second invocation costs almost
nothing.

**Why ignore-unfixed on the gate?** A gate that blocks on findings nobody
can act on teaches people to bypass it, and I think a bypassed gate is
worse than none — it produces confidence nobody earned. Unfixable findings
still land on my reporting surface. They just do not block merges.

**Why a registry-backed BuildKit cache with mode=max?** The expensive
layers of my multi-stage Go build live in the discarded builder stage, and
mode=min exports only the final image's layers. I measured the difference
live — a cold build took about 49 seconds, and a cleared-cache build
importing only the registry cache took about 2. I also keep the cache
repository distinct from the release repository, so a cache layer can never
be mistaken for a release artifact.

## Gotchas hit in this project

* A distroless nonroot image needs an explicit `runAsUser` in the pod spec
  or Kubernetes cannot verify the non-root constraint — found live in the
  tracer.
* The registry has two addresses — `localhost:5000` from the host and
  `athena-registry:5000` in-cluster. Pushing to one and referencing the
  other is the standard k3d trap.
* Exception entries in `.trivyignore` fail CI unless each carries a
  justification comment — my lint treats an unjustified suppression as a
  red build, not a style issue.

## War stories

**The stale-image bug.** During the stateful-layer work my deployed pod
predated the login code I was testing against — the manifests were right,
the tag was right, and the behaviour was wrong, because the image behind
the tag had been built before the feature existed. I rebuilt, re-pinned to
the new immutable tag, and adopted the rule that a tag is proven by what
the registry serves, not by what the git log implies.

## Command cheat-sheet

```bash
curl -s http://localhost:5000/v2/athena-media/tags/list | python3 -m json.tool
docker buildx build --load -t localhost:5000/athena-media:$(git rev-parse --short HEAD) src/media
bash scripts/check-trivyignore.sh          # justification lint for the exception register
trivy image --severity HIGH,CRITICAL --ignore-unfixed localhost:5000/athena-media:<tag>
```
