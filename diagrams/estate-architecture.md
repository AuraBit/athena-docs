# Estate Architecture

The runtime picture: what actually runs on this one host, right now, and
what later phases add. Every solid-bordered element below is asserted live
by a named verification script in `athena-infra/scripts/`; every
dashed-bordered element is a documented future addition, labelled with the
phase that introduces it. Nothing is drawn as real unless a verification
check or an ADR backs it — see the element table below the diagram.

```mermaid
graph TB
    classDef future fill:#eee,stroke:#999,stroke-width:1px,stroke-dasharray: 5 5,color:#666;

    subgraph HOST[Host machine - Arch Linux]
        DNSMASQ[dnsmasq - wildcard DNS<br/>athena.net to 127.0.0.1<br/>platform.athena.net to 127.0.0.2]
        MKCERT[mkcert root CA<br/>host CAROOT, browser-trusted]
        RUNNER[self-hosted runner<br/>athena-runner, ephemeral JIT config]
        ACTCLI[act CLI<br/>local workflow inner loop]

        subgraph DOCKER[Docker daemon]
            subgraph APP[k3d cluster app - loopback 127.0.0.1 port 443]
                APPLB[serverlb]
                APPSRV[server, tainted<br/>CriticalAddonsOnly NoExecute]
                APPAGENTS[3x agent, untainted]
                APPEG[Envoy Gateway<br/>Gateway API]
                APPCM[cert-manager<br/>ClusterIssuer mkcert-issuer]
                APPNS[dev / stg / prod namespaces]
                APPFUTURE[Athena workloads: media + datastores + athena-shop in dev, stg, prod namespaces]
            end

            subgraph PLATFORM[k3d cluster platform - loopback 127.0.0.2 port 443]
                PLATLB[serverlb]
                PLATSRV[server, tainted<br/>CriticalAddonsOnly NoExecute]
                PLATAGENTS[2x agent, untainted]
                PLATEG[Envoy Gateway<br/>Gateway API]
                PLATCM[cert-manager<br/>ClusterIssuer mkcert-issuer]
                PLATARGO[ArgoCD 3.4.6 hub — app cluster registered as remote destination]
                PLATOBS[FUTURE Phase 4 - Prometheus, Grafana, Loki, Alloy]
                PLATVAULT[FUTURE Phase 5 - Vault]
                PLATSONAR[FUTURE Phase 7 - SonarQube]
            end

            REGISTRY[athena-registry, k3d-managed<br/>host localhost 5000, in-cluster athena-registry 5000]
            LOCALSTACK[LocalStack container<br/>docker-compose, systemd-managed]
        end
    end

    GITHUB[GitHub SaaS, external<br/>org AuraBit, four repos]

    DNSMASQ -.resolves athena.net.-> APPLB
    DNSMASQ -.resolves platform.athena.net.-> PLATLB
    MKCERT ==CA secret==> APPCM
    MKCERT ==CA secret==> PLATCM
    RUNNER --host Docker daemon--> DOCKER
    RUNNER -.JIT-registered at org level.-> GITHUB
    ACTCLI --host Docker daemon--> DOCKER
    REGISTRY -.pulled by containerd.-> APP
    REGISTRY -.pulled by containerd.-> PLATFORM
    LOCALSTACK -.host.k3d.internal 4566.-> APP
    LOCALSTACK -.host.k3d.internal 4566.-> PLATFORM
    LOCALSTACK -.localhost 4566, host and CI and Terraform.-> HOST

    class PLATOBS,PLATVAULT,PLATSONAR future;
    %% Phase 3 delivered APPFUTURE and PLATARGO (03-10)
```

## Legend

* **Solid border** — exists today, asserted live by a named verification
  script.
* **Dashed, grey-filled border** — future addition, labelled with the phase
  that introduces it. Never asserted by any check that exists today.
* A dotted arrow (`-.->`) is a network/resolution relationship (DNS
  resolution, image pull, LocalStack reachability, JIT registration). A
  solid or thick arrow is a process/control relationship (a CA secret
  materialized into a cluster, a host process using the Docker daemon).

## Element-to-verification-check-to-ADR table

Every drawn, solid-bordered element below is traceable to a real
verification check under `athena-infra/scripts/` and to the ADR that
explains why it is shaped that way. An element with no verification check
and no ADR would be either undocumented or aspirational — this table is
what keeps the diagram honest.

| Element | Verification check | ADR |
|---|---|---|
| dnsmasq wildcard DNS | `scripts/verify-skeleton.sh` (DNS resolution for both domains) | `athena-infra` [ADR-0003](../../athena-infra/docs/adr/0003-local-dns-and-tls.md) |
| mkcert root CA -> cert-manager `ClusterIssuer` | `scripts/verify-skeleton.sh` (served-cert-issuer-matches-CAROOT check) | `athena-infra` [ADR-0003](../../athena-infra/docs/adr/0003-local-dns-and-tls.md) |
| `app` k3d cluster (server taint, agent count, no bundled Traefik) | `scripts/verify-skeleton.sh` (node count/Ready, taint placement, no Traefik pod) | `athena-infra` [ADR-0001](../../athena-infra/docs/adr/0001-k3d-dual-cluster-shape.md) |
| `platform` k3d cluster (server taint, agent count) | `scripts/verify-clusters.sh` (platform node count/taint) | `athena-infra` [ADR-0001](../../athena-infra/docs/adr/0001-k3d-dual-cluster-shape.md) |
| Envoy Gateway (both clusters) | `scripts/verify-skeleton.sh` / `scripts/verify-clusters.sh` (Gateway Programmed, HTTPS 200) | `athena-infra` [ADR-0002](../../athena-infra/docs/adr/0002-envoy-gateway-as-gateway-api-implementation.md) |
| cert-manager (both clusters) | `scripts/verify-skeleton.sh` / `scripts/verify-clusters.sh` (Certificate Ready) | `athena-infra` [ADR-0003](../../athena-infra/docs/adr/0003-local-dns-and-tls.md) |
| dev / stg / prod namespaces (app cluster only) | `scripts/verify-clusters.sh` (namespace placement, environment label, absent on platform) | `athena-docs` [ADR-0008](../adr/0008-namespaces-vs-clusters-for-environments.md) |
| `athena-registry` (shared, both clusters and host) | `scripts/verify-clusters.sh` (invokes `scripts/registry-smoke.sh` — host push, in-cluster pull, both clusters) | `athena-infra` [ADR-0001](../../athena-infra/docs/adr/0001-k3d-dual-cluster-shape.md) |
| LocalStack container | `scripts/verify-localstack.sh` (systemd state, health, real S3 round trip, in-cluster reachability) | `athena-infra` [ADR-0004](../../athena-infra/docs/adr/0004-localstack-as-a-host-service.md) |
| Self-hosted runner (`athena-runner`) | `scripts/verify-runner.sh` (unit state, org-registered, ephemeral via `.runner` file, no PAT leakage) | `athena-infra` [ADR-0005](../../athena-infra/docs/adr/0005-ephemeral-jit-self-hosted-runner.md) |
| `act` CLI | `scripts/verify-runner.sh` (act version/list/run) | `athena-infra` [ADR-0005](../../athena-infra/docs/adr/0005-ephemeral-jit-self-hosted-runner.md) |
| GitHub org, four repos | `scripts/verify-governance.sh` (org policy, per-repo ruleset shape) | `athena-docs` [ADR-0005](../adr/0005-github-org-and-governance-as-code.md) |

## What this diagram does not claim

Per `athena-infra` ADR-0001's honest caveat: every node drawn inside either
k3d cluster is a container sharing this one host's kernel and Docker
daemon. This diagram shows scheduling topology (which node a workload
lands on, which node is tainted) — it does not represent failure isolation
the way a diagram of real, separate EC2-backed EKS worker nodes would. See
`athena-infra/docs/cluster-topology.md`'s "How this diverges from EKS"
section for the full statement.
