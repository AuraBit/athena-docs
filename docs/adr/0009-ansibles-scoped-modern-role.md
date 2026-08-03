# 0009. Ansible's Scoped, Modern Role

* Status: accepted
* Date: 2026-08-03
* Deciders: Yahia Tarek (YahiaEng)
* Tier: short-form

## Context

The project's fixed tool list includes Ansible, but a cloud-native estate
built on Terraform, Kubernetes, and GitOps has already replaced most of
what configuration management traditionally did. The question this ADR
answers is not "why Ansible" (it's a fixed commitment) but "what is Ansible
actually for here, and why isn't that scope larger" — a question worth
answering honestly rather than padding Ansible's role artificially to look
busier than it is.

## Decision

Ansible provisions **host-level bootstrap only**: wildcard DNS
(`bootstrap-dns`, dnsmasq config), LocalStack as a host-level systemd
service (`bootstrap-localstack`), and the self-hosted GitHub Actions runner
(`github-runner`, JIT-config credential flow, systemd unit). Everything
that runs **inside** either Kubernetes cluster is declarative and
GitOps-reconciled instead — Helm charts, Kustomize overlays, cert-manager
`Certificate` objects, ArgoCD Applications (Phase 3+) — none of it goes
through an Ansible playbook.

## Consequences

* The honest framing, stated directly rather than implied: Ansible's role
  in this project **shrank**, it didn't disappear. It provisions the host
  a Kubernetes cluster runs on top of; it does not provision anything the
  cluster itself can reconcile declaratively. That boundary — configuration
  management stops exactly at the host, GitOps takes over inside the
  cluster — is itself the interview-relevant story: "why doesn't this
  project use Ansible for more?" has a concrete, defensible answer instead
  of a hand-wave.
* Every Ansible role this project writes (`bootstrap-dns`,
  `bootstrap-localstack`, `github-runner`) is production-shaped, not a
  throwaway script: idempotent, checked-desired-state-first, using
  `community.docker` for real compose-lifecycle idempotency rather than
  shelling out blindly — the reduced *scope* does not mean reduced
  *quality* for what remains in scope.
* `ansible/site.yml` aggregates all three roles in dependency order
  (dns -> localstack -> runner) into one re-runnable playbook, so "what
  does host bootstrap actually do end to end" has one answer, not three
  separately-remembered playbooks.
* If a future phase needs host-level provisioning beyond these three roles
  (e.g. a new host-level service), the same boundary rule applies: does it
  run on the host, outside any cluster's reconciliation loop? If yes,
  Ansible. If it's a workload a cluster can run, it's Helm/Kustomize/
  ArgoCD instead, not a new Ansible role.
