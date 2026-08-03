# LocalStack and AWS Emulation

* Tool: LocalStack
* Summary: API-compatible AWS emulator, running as a host service outside both clusters, with an honest per-service coverage split rather than an assumed one
* Phase introduced: 01-local-foundations-repo-governance
* Related ADRs: athena-infra/docs/adr/0004-localstack-as-a-host-service.md
* Last reviewed: 2026-08-03

## Mental model

LocalStack is an API-compatible *emulator* of AWS service endpoints, not
AWS itself — it answers the same REST/JSON wire protocol real AWS services
do, closely enough that the AWS CLI, SDKs, and the Terraform AWS provider
generally can't tell the difference for supported services. It lives
outside and outlives either k3d cluster: a host-level `docker-compose`
service under systemd, reachable at `localhost:4566` from the host/CI and
at `host.k3d.internal:4566` from inside either cluster's pods — the local
stand-in for "this project's one AWS account."

## Common interview questions

**What is emulation good for, and where does it stop?** Good for exercising
the actual API surface your IaC calls — create/read/update/delete
semantics, IAM-style permission checks, S3 object lifecycle — at zero cost
and with instant iteration. It stops the moment a service's behaviour
depends on something the free tier doesn't implement at all
(license-gated) or can't meaningfully implement locally regardless of tier
(CloudFront's actual global edge network has no local stand-in).

**How do you avoid false confidence from a passing test against an
emulator?** Never trust the health endpoint's own optimism — call the real
API and inspect the actual response, and record the verification mode
(`emulated` vs. `code+docs-only`) explicitly, per service, rather than
inferring "the container answered 200" means "this service genuinely
works here."

**Why does this estate verify every apply with a read-back?** A green
`terraform apply` against an emulator that silently no-ops, partially
implements, or fakes success is indistinguishable from a real apply unless
something independently confirms the resource actually exists and behaves
as expected. The S3 round trip (create bucket, put an object, get it back,
assert the body byte-for-byte, delete) exists specifically to catch that
gap — a health check alone would not have.

**What are the tradeoffs of emulation versus a real AWS sandbox account?**
Emulation is free and instant but carries real coverage gaps (RDS,
ElastiCache, CloudFront, and EKS are license-gated on this project's free
Hobby tier). A real sandbox account has zero fidelity gap but costs real
money — incompatible with this project's hard $0 constraint, which is the
entire reason the tradeoff exists in the first place.

## Gotchas hit in this project

**The auth-token gate.** Since 2026-03-23, LocalStack's unified image
refuses to work meaningfully without `LOCALSTACK_AUTH_TOKEN` set — but a
token-less container still answers `/_localstack/health` with `200`
(looking "up") while rejecting most real service calls underneath. A
`docker-compose.yml` copied from a pre-2026 tutorial would silently produce
exactly this half-working state, passing a naive "is it up" check while
doing nothing real.

**The free tier's coverage gap, confirmed rather than assumed.** The Hobby
tier's own `/_localstack/health` endpoint optimistically lists `rds`,
`elasticache`, `cloudfront`, and `eks` as `"available"` regardless of
actual license coverage — trusting that field alone would have
(incorrectly) marked all four as genuinely emulated. A real API call
against each — `rds describe-db-instances`, `elasticache
describe-cache-clusters`, `cloudfront list-distributions`, `eks
list-clusters` — returns a license-gated `InternalFailure` instead. Report
coverage exactly as `docs/localstack-service-coverage.md` records it: `s3`,
`iam`, and `ec2` genuinely emulated (confirmed live via a real round trip);
`rds`, `elasticache`, `cloudfront`, and `eks` code+docs-only.

## War stories

**The fake-success problem.** A system that reports healthy or successful
while doing nothing real underneath is a recurring, well-known class of
production incident — a health check that only pings an open socket, a
deploy pipeline that reports "success" on a job that silently did nothing.
This is precisely why Phase 2's requirement is a post-apply *verification*
(a real read-back proving the resource exists and behaves correctly), not
merely a green `terraform apply`. LocalStack's own optimistic health
endpoint is a live, concrete instance of exactly this failure class inside
this project, not a hypothetical one borrowed from a blog post.

## Command cheat-sheet

```bash
curl -sS http://localhost:4566/_localstack/health | jq .
awslocal s3 mb s3://test-bucket          # awslocal wraps --endpoint-url http://localhost:4566
aws --endpoint-url http://localhost:4566 s3 ls
aws --endpoint-url http://localhost:4566 rds describe-db-instances   # license-gated InternalFailure on Hobby
docker compose -f localstack/docker-compose.yml logs -f localstack
```
