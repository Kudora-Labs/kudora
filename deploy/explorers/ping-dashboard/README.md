# Ping Dashboard Localnet Integration

This directory contains the Ping Dashboard / Ping.pub-style explorer integration for the Kudora Docker localnet.

Runtime scope:

- local-only Cosmos explorer UI
- local-only UI URL: `http://localhost:18088`
- local chain config:
  - Cosmos chain-id `kudora_12000-1`
  - base denom `akud`
  - display denom `KUD`
  - decimals `18`
  - bech32 prefix `kudo`

The image is built locally from the official `ping-pub/explorer` upstream commit inspected during Phase 14 and bakes in the Kudora localnet chain config.

Repository root commands:

```bash
make ping-dashboard-up
make ping-dashboard-smoke-test
make ping-dashboard-down
make ping-dashboard-reset
```

This is not a production explorer deployment.
