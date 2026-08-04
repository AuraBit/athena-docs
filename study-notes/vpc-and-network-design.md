# VPC and Network Design

* Tool: VPC and network design (three-tier subnet topology)
* Summary: A VPC is a private address space with tiers that trade internet reach for isolation, and every trade this module makes is proven twice, once in a plan and once against the live network
* Phase introduced: 02-core-network-terraform-ci-verification-pattern
* Related ADRs: athena-infra/docs/adr/0010-in-house-network-modules.md
* Last reviewed: 2026-08-04

## Mental model

A VPC is a private, isolated address space in one region, and the three-
tier subnet split this module builds buys me a graduated answer to one
question for every workload, how much of the internet can this thing
reach, directly, through NAT, or not at all. Public gets a route straight
to the internet gateway, private-app gets NAT-only egress, and private-
data gets no default route anywhere outside the VPC at all.

## Common interview questions

**Why three subnet tiers rather than two?** Two tiers, public and
private, only answers whether something faces the internet. I need a
third answer for data, whether something can even initiate a connection
outward at all, because a database or a cache holding real data is
exactly the workload I do not want quietly phoning out if it is ever
compromised. `modules/core-network/routes.tf` gives private-data its own
route table with no `0.0.0.0/0` route of any kind, and that absence is
the whole point of the tier, not an oversight a reviewer should flag.

**What does the private-data tier's lack of a default route actually
guarantee, and how would you prove it?** It guarantees that nothing in
that tier can reach the internet, not through NAT, not through the
internet gateway, full stop, because there is no route to try. I prove it
two separate ways in this estate. `modules/core-network/tests/core-network.tftest.hcl`
runs a mock-provider plan assertion, `no_private_data_default_route`,
that checks the planned route table has no such route before anything is
ever applied. `scripts/verify-network.sh` independently calls
`describe-route-tables` against the real, applied route tables and
asserts the same absence there too. Saying both of those out loud, a
plan-time check and a live describe-time check agreeing with each other,
is a stronger answer than either one alone.

**How do you decide NAT gateway cost versus availability?** A NAT gateway
bills per hour it exists plus per gigabyte it processes, so one NAT per
availability zone multiplies the fixed cost by the zone count. In dev I
take the single-NAT saving and accept that losing that one zone removes
private-app egress entirely, because dev does not need to survive a zone
failure. In stg and prod I run one NAT per zone, so losing a zone only
takes out that zone's own egress, and stg deliberately matches prod's
topology here rather than dev's, so stg can genuinely rehearse a zone
failure before prod ever needs to.

**What is a gateway endpoint, and how does it differ from an interface
endpoint?** A gateway endpoint works by injecting a route for its AWS-
managed prefix list directly into whatever route tables I attach it to,
so it takes no security group and no ENI at all. An interface endpoint
attaches to subnets instead, gets its own ENI and IP address, and does
take a security group, because traffic actually terminates on it. My S3
endpoint in `modules/core-network/endpoints.tf` is a gateway endpoint,
and that is why it can attach to private-data's route table with nothing
else to configure.

**Why can the private-data tier reach S3 with no internet path at all?**
I attach the same S3 gateway endpoint to private-data's route table
directly, alongside private-app's, so S3 traffic never leaves the VPC and
never touches NAT or the internet gateway. That is simultaneously the
security story, no internet egress needed for S3 access, and the cost
story, no NAT data-processing charges for it.

**Why take over the default security group rather than ignoring it?**
AWS creates one with every VPC, and its stock rules allow everything in
and out, and I cannot delete it, only adopt and edit it. The default
group is exactly where an instance lands the moment somebody forgets to
specify one, so leaving it permissive means the least-careful path
through this estate is also the least-secure path. `modules/core-network/security-groups.tf`
adopts it and declares zero ingress and zero egress rules, so that same
mistake instead produces a workload with no network access at all, loud
and visible instead of quiet and dangerous.

**How do you plan address space across environments so they could be
peered later without renumbering?** I give every environment its own
non-overlapping `/16` supernet, dev at `10.0.0.0/16`, stg at
`10.1.0.0/16`, prod at `10.2.0.0/16`, documented in
`docs/ipam-allocation.md`. If two environments ever needed a peering
connection or a transit attachment between them, overlapping ranges
would make that impossible without renumbering one of them live.
Choosing disjoint supernets up front costs me nothing today and removes
a whole category of painful future migration.

## Gotchas hit in this project

**Choosing `for_each` over `count` for subnets was not a stylistic
preference, it protects against a real renumbering hazard.**
`modules/core-network/subnets.tf` keys every subnet by a stable
`<tier>-<az>` string rather than a numeric position, because `count`
indexes resources by list position, and adding or removing one
availability zone from the list would renumber every subnet after it,
destroying and recreating subnets that never actually changed. Keying by
tier and AZ means only the AZ genuinely added or removed is ever touched.

**The module's own deliberate mutation tests caught exactly the class of
regression they were built to catch.** `modules/core-network/tests/core-network.tftest.hcl`
and `nat-topology.tftest.hcl` assert plan-time invariants like the
private-data no-default-route rule directly against a mocked plan, before
anything applies, which is what let me catch a broken route assumption
at plan time rather than discovering it live against LocalStack later.

## War stories

The industry incident this topology defends against is a data-tier host
that was never supposed to reach the internet quietly exfiltrating data
outward, because nobody actually verified the route table, only assumed
the subnet diagram meant what it said. The concrete control in this
estate is private-data's genuinely routeless route table in
`modules/core-network/routes.tf`, checked twice, once by
`no_private_data_default_route` at plan time and once by
`scripts/verify-network.sh` against the live, applied network, so this
estate never has to trust the diagram alone.

## Command cheat-sheet

```bash
terraform test -filter=tests/core-network.tftest.hcl
bash scripts/verify-network.sh dev
aws --endpoint-url http://localhost:4566 ec2 describe-route-tables \
  --filters Name=tag:Tier,Values=private-data
terraform console   # cidrsubnet("10.1.0.0/16", 4, 0)
```
