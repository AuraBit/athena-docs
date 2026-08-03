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

**What is a CA actually, and what does "trusted" concretely mean?** A
certificate authority is just a keypair, and trust is just where its
public half lives. I install mkcert's local-only root CA straight into
this host's trust store with `mkcert -install`, and that one command
touches every store that matters here — the OS trust bundle, the
browser's own NSS store where one exists, and curl's OpenSSL bundle.
Once the public certificate sits in a store, that store accepts
anything the CA signed, no questions asked. That also means these
certificates are trusted on exactly one machine, this developer's own
laptop, and I call that the correct, honestly scoped answer for a local
project, not a shortfall.

**Why declarative `Certificate` objects instead of imperatively created
secrets, in a GitOps estate?** We declare `Certificate` manifests in
git instead of running `kubectl create secret tls` by hand, because the
imperative version becomes permanent drift the moment ArgoCD starts
watching this cluster in Phase 3. There's no git commit for ArgoCD to
compare that secret against, so it just sits outside the reconciliation
loop forever, silently. A declared `Certificate` object gives
cert-manager something to reconcile and auto-renew the same way
everything else in this estate gets reconciled, which is exactly the
declarative-over-imperative principle we wrote down as D-13. I still
keep the raw `kubectl create secret tls` command around as a documented
break-glass fallback, but it's never the default path.

**How does wildcard DNS differ from hosts entries, and when is each
right?** One dnsmasq `address=/domain/IP` rule answers every subdomain
under a domain, full stop. `/etc/hosts` can't do that at all — it needs
its own literal line for every single subdomain, and it has no wildcard
concept whatsoever. So I reach for hosts entries when there's a small,
fixed handful of hostnames, and I reach for wildcard DNS the moment an
estate needs to serve arbitrary subdomains under `*.athena.net`, which
is exactly this project's case.

**What changes when this becomes a real ACME issuer (e.g. Let's
Encrypt)?** Only one thing changes, and it's the `ClusterIssuer`'s
backing. Swap the local CA secret for an ACME solver, either an HTTP-01
or a DNS-01 challenge, and the CA behind every certificate becomes a
publicly trusted one instead of a root I installed myself. The
`Certificate` object shape stays identical, and cert-manager's own
reconciliation loop stays identical too. That's exactly why I used
cert-manager here instead of writing a bespoke local-only TLS script —
it's the right practice even for a project that will never actually
talk to a real ACME server.

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
