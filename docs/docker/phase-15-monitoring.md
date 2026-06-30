# Phase 15 Monitoring

Phase 15 adds a local-only Docker monitoring stack for the currently validated Kudora runtime baseline:

- Cosmos SDK localnet
- EVM JSON-RPC
- CosmWasm runtime
- the generic `x/integrity` module baseline

It does not add new protocol modules or production monitoring infrastructure.

## Prerequisite

Start the localnet first:

```bash
make localnet-init
make localnet-up
```

## Commands

```bash
make monitoring-up
make monitoring-smoke-test
make monitoring-logs
make monitoring-down
make monitoring-reset
make phase-15-validate
```

## Local URLs

- Prometheus: `http://localhost:19090`
- Grafana: `http://localhost:3000`

Grafana local-only credentials:

- username: `admin`
- password: `admin`

These defaults are documented and committed only because this stack is localnet-only. They are not acceptable for production deployment.

## Scrape And Probe Coverage

The current stack covers:

- CometBFT Prometheus metrics on `26660`
- CometBFT RPC `/status`
- Cosmos REST `node_info`
- EVM JSON-RPC `eth_chainId`
- Grafana health

The expected runtime identity remains:

- Cosmos chain-id: `kudora_12000-1`
- EVM chain ID: `120001`
- expected `eth_chainId`: `0x1d4c1`

## Provisioned Dashboards

- `Kudora Localnet Overview`
- `Kudora EVM`
- `Kudora CosmWasm + Integrity`

The dashboards are committed directly in the repository and loaded through Grafana provisioning. No external Grafana.com import is required during validation.

## Native Metrics Versus Smoke Coverage

CometBFT exports native metrics that Prometheus can scrape directly.

CosmWasm and `x/integrity` do not yet export dedicated domain-specific Prometheus metrics in this phase. Instead:

- the dashboards keep the localnet endpoint health visible;
- `make wasm-smoke-test` validates store / instantiate / execute / query behavior;
- `make integrity-smoke-test` validates tenant registration, encrypted commitment flow, and ownership transfer behavior.

This avoids inventing fake runtime metrics while still making the current baseline observable.

## Explorer Relationship

Phase 14 explorers remain supported and their smoke validation is preserved, but they are not yet first-class Prometheus scrape targets in Phase 15. Explorer health remains validated through:

```bash
make explorers-up
make explorers-smoke-test
make explorers-down
```

## Local-Only State Policy

- Prometheus TSDB data remains in Docker-managed volumes only
- Grafana state remains in Docker-managed volumes only
- temporary smoke artifacts remain under `tmp/phase-15-monitoring/`
- no monitoring secret or production credential is committed

## Not Included Yet

Phase 15 still does not include:

- Alertmanager
- container/node exporters
- remote metrics storage
- production alert routing
- Kubernetes
- public monitoring exposure
- future protocol-module observability

This is a localnet observability baseline, not a production monitoring runbook.

Phase 16 does not change the monitoring topology. It only adds mainnet-genesis preparation and validation tooling, so the monitoring stack remains localnet-only and non-production.

Phase 17 also leaves the monitoring stack unchanged. Candidate release and
Cosmovisor packaging do not add production monitoring or alter the local
Prometheus/Grafana topology.
