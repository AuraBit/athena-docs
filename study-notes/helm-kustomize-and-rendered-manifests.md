# Helm, Kustomize, and Rendered Manifests

* Tool: Helm (template-time only) + Kustomize overlays, rendered into plain YAML
* Summary: Helm parameterises the base once, Kustomize specialises per environment, and the cluster only ever sees committed plain YAML
* Phase introduced: 03-app-ci-cd-walking-skeleton
* Related ADRs: athena-gitops/docs/adr/0002-rendered-manifests-and-the-config-repo-split.md
* Last reviewed: 2026-08-04

## Mental model

Three layers with one-way flow. The Helm chart holds the shared shape, the
per-environment values files hold the deliberate differences, and a
Kustomize overlay folds the rendered output into environment specifics like
namespace and image pin. The committed product — plain YAML under
`envs/<env>/<unit>/` — is the only thing ArgoCD syncs. Rendering happens at
commit time through one canonical script, so the PR diff IS the cluster
diff.

## Common interview questions

**Why render at commit time instead of letting ArgoCD run Helm?** I want
the thing a reviewer approves to be the thing that applies. With
controller-side rendering, the reviewed diff is a values change and the
real manifests materialise later, rendered by whatever Helm binary the
controller bundles. A template bug then surfaces at sync time, in the
cluster. My rendered-manifests approach moves that failure into CI and
makes drift legible.

**Why not Kustomize's Helm inflator?** I rejected `--enable-helm` because
it is documented as experimental and shells out to a Helm v3 binary
specifically, while the ecosystem default is now v4. That is a hidden
version coupling in the render path. My pipe of `helm template` into
`kustomize build` keeps each tool doing the one thing it is best at.

**Where does the image tag live and why there?** I keep it in the overlay's
Kustomize image transformer — one value, one file, per environment. I
deliberately keep it out of the chart's values, where a chart change and an
image change would collide in the same diff. Promotion is copying that one
value forward, and rollback is reverting the commit that changed it.

**How do you keep rendered output honest?** I assert two properties instead
of trusting them. A CI render-check fails any change whose committed
`envs/` does not match a fresh render byte for byte, so rendered output
cannot go stale. And the render is deterministic — I prove it by rendering
twice and requiring zero diff.

## Gotchas hit in this project

* Helm's `--show-only` errors with "could not find template" when a
  conditional template renders empty — prod's disabled load generator hit
  this. My script invokes helm per template and tolerates exactly that
  case, loudly.
* GitHub's ruleset API silently drops an Integration-type bypass actor for
  the Actions app, so a CI job can never push a render to protected main.
  The render-check design exists because I verified that live.
* `rendered-input.yaml` is a transient intermediate — it stays gitignored,
  and only the kustomize output is committed.

## War stories

**The render that could not push.** My first render workflow design had CI
regenerate `envs/` and push the result with its own token. The push was
blocked by the ruleset, and the "obvious" fix — a bypass entry for the
Actions integration — was accepted by the API and then silently absent from
every subsequent read, while Terraform state insisted it existed. I
reverted the bypass, flipped the workflow to a pure check, and moved
rendering onto the committing actor. Invisible drift between state and
reality is the worst failure mode Terraform can have, and I chose the
design that structurally cannot produce it.

## Command cheat-sheet

```bash
bash scripts/render-env.sh dev            # render every dev unit
bash scripts/render-env.sh prod media     # one env, one unit
git diff --exit-code envs/                # the render-check's own assertion
grep -c '{{' envs/dev/media/all.yaml      # 0 = plain YAML, no leaked templating
```
