# Blockscout Localnet Integration

This directory contains the Blockscout integration for the Kudora Docker localnet.

Runtime scope:

- local-only EVM explorer
- target JSON-RPC endpoint: `http://kudora-validator-0:8545` on the shared Docker network
- local-only UI URL: `http://localhost:4000`
- local-only API base URL: `http://localhost:4000/api/v2`

The compose stack uses official Blockscout images pinned by digest and keeps all database/cache state inside Docker-managed local volumes.

Repository root commands:

```bash
make blockscout-up
make blockscout-smoke-test
make blockscout-down
make blockscout-reset
```

This is not a production deployment manifest and it does not expose any public secrets.
