# Kudora Monitoring

This directory contains the local-only Docker monitoring stack introduced in Phase 15.

It is intentionally limited to:

- Prometheus
- Grafana
- blackbox-exporter

The stack attaches to the existing Kudora localnet Docker network and does not replace the localnet runtime.

## Commands

```bash
make localnet-init
make localnet-up
make monitoring-up
make monitoring-smoke-test
make monitoring-logs
make monitoring-down
make monitoring-reset
```

## Local URLs

- Prometheus: `http://localhost:19090`
- Grafana: `http://localhost:3000`

Local-only Grafana credentials:

- username: `admin`
- password: `admin`

These defaults are acceptable only because the stack is localnet-only and not production-ready.

## Scrape Targets

The monitoring stack scrapes or probes:

- Kudora CometBFT metrics on `kudora-validator-0:26660`
- CometBFT RPC `/status`
- Cosmos REST `node_info`
- EVM JSON-RPC `eth_chainId`
- Grafana health

Explorer health remains validated by the Phase 14 explorer smoke scripts rather than native Prometheus targets in this phase.

## Dashboards

Provisioned dashboards:

- `Kudora Localnet Overview`
- `Kudora EVM`
- `Kudora CosmWasm + Integrity`

The dashboards are committed as JSON and do not depend on external Grafana marketplace imports during validation.

## Local-Only State Policy

- generated Prometheus TSDB data stays in Docker-managed volumes only
- generated Grafana state stays in Docker-managed volumes only
- temporary monitoring smoke artifacts stay under `tmp/phase-15-monitoring/`
- no monitoring `.env` file with real secrets may be committed

## Not Production-Ready

This stack is for local developer validation only. It does not include:

- Alertmanager
- remote storage
- Kubernetes deployment
- public RPC hardening
- production Grafana authentication
- monitoring for future protocol modules that Kudora has not integrated yet
