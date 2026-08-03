# cert-manager, mkcert, and Local DNS

* Tool: cert-manager + mkcert + dnsmasq
* Summary: Three separable concerns — resolution, issuance, trust — solved independently to produce a genuinely browser-trusted local *.athena.net
* Phase introduced: 01-local-foundations-repo-governance
* Related ADRs: athena-infra/docs/adr/0003-local-dns-and-tls.md
* Last reviewed: 2026-08-03

## Mental model

Three concerns people habitually conflate, solved independently here: name
**resolution** (which IP does a hostname point to — dnsmasq), certificate
**issuance** (who signs a certificate asserting "this really is
`athena.net`" — cert-manager, reconciling declarative `Certificate`
objects), and **trust** (does the client verifying that signature actually
recognize the issuer as authoritative — mkcert's root CA, installed into
this host's own trust store). None of the three implies the others; keeping
them conceptually separate is what makes each piece's actual job legible.

## Common interview questions

**What is a CA actually, and what does "trusted" concretely mean?** A CA is
just a keypair whose public half sits in a verifier's trust store;
"trusted" means that specific store (an OS trust bundle, a browser's own
NSS store, curl's OpenSSL bundle) contains that CA's public certificate and
will therefore accept anything it signed. mkcert generates a local-only
root CA and installs it into the host's trust store via `mkcert -install`
— this project's certificates are "trusted" only on this one developer's
machine, which is the correct, honestly-scoped answer for a local project,
not an oversight.

**Why declarative `Certificate` objects instead of imperatively created
secrets, in a GitOps estate?** An imperative `kubectl create secret tls`
becomes permanent, unreconciled drift the instant ArgoCD starts watching a
cluster in Phase 3 — there is no git commit for ArgoCD to compare that
Secret against, so it silently sits outside the reconciliation loop
forever. Declaring `Certificate` manifests in git lets cert-manager
reconcile and auto-renew them the same way everything else in this estate
is reconciled — matching the declarative-over-imperative principle (D-13).
Raw `kubectl create secret tls` remains a documented break-glass fallback,
never the default path.

**How does wildcard DNS differ from hosts entries, and when is each
right?** A dnsmasq `address=/domain/IP` rule answers infinite subdomains
with one config line; `/etc/hosts` needs a literal line per subdomain and
has no wildcard concept at all. Hosts entries are right for a handful of
fixed hostnames; wildcard DNS is right the moment an estate serves
arbitrary `*.athena.net` subdomains, which is exactly this project's case.

**What changes when this becomes a real ACME issuer (e.g. Let's
Encrypt)?** Only the `ClusterIssuer`'s backing changes — from a local CA
secret to an ACME solver (HTTP-01 or DNS-01 challenge) — and the CA becomes
a publicly-trusted one instead of a locally-installed root. The
`Certificate` object shape and cert-manager's own reconciliation loop stay
identical either way, which is exactly why using cert-manager here (instead
of a bespoke local-only TLS script) is the right practice even for a
project that will never actually talk to a real ACME server.

## Gotchas hit in this project

**dnsmasq's several near-identical directives.** `address=`, `server=`, and
`local=` all sound like plausible ways to configure a domain's resolution,
but only `address=/domain/IP` is the wildcard-answer directive this project
actually needs — getting the directive wrong produces a resolver that
silently answers nothing for the domain, or forwards the query upstream
instead of answering it locally, with no obvious error to point at the
cause.

**curl and a browser consult different trust stores.** curl on this host
uses the system/OpenSSL trust bundle, which `mkcert -install` updates
directly; a browser may consult its own separate NSS trust store on some
platforms. A green `curl -sS -o /dev/null -w '%{ssl_verify_result}'`
therefore proves less than it appears to — this project's own tracer plan
required an actual browser padlock check (not just a passing curl call) for
exactly this reason, because a curl-only verification can pass while a real
browser still shows a certificate warning.

## War stories

**The mkcert root CA private key is a real credential, not a throwaway
dev artifact.** Once `mkcert -install` runs, this host's browsers and OS
trust anything signed by that root CA with no warning at all. Anyone who
obtained that private key could mint a certificate for *any* domain this
host would silently accept — enabling transparent, undetectable
interception of this developer's own HTTPS traffic across every site the
browser visits, not just `*.athena.net`. This is exactly why the CA root
never leaves `mkcert -CAROOT` on the local filesystem and is never checked
into any of the estate's four git repositories; only the *derived*
cert-manager `Secret` (a cluster-scoped signing capability built from that
root, not the root key itself) is ever materialized into Kubernetes.

## Command cheat-sheet

```bash
mkcert -CAROOT
kubectl get certificate athena-net-wildcard -o jsonpath='{.status.conditions}'
kubectl get clusterissuer mkcert-issuer -o jsonpath='{.status.conditions}'
curl -sS -o /dev/null -w '%{http_code} %{ssl_verify_result}\n' https://hello.athena.net
```
