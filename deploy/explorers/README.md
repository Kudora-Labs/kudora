# Kudora Docker Explorers

This directory contains the Docker-based local explorers for the current Kudora localnet baseline:

- Blockscout for the EVM JSON-RPC surface
- Ping Dashboard / Ping.pub-style explorer for the Cosmos SDK and CosmWasm surface

These explorers target the current local runtime only:

- Cosmos chain-id `kudora_12000-1`
- EVM chain ID `120001`
- expected `eth_chainId = 0x1d4c1`

They are localnet-only and are not production deployment manifests.

Primary commands from the repository root:

```bash
make localnet-up
make explorers-up
make explorers-smoke-test
make explorers-logs
make explorers-down
make explorers-reset
```

See `docs/docker/phase-14-explorers.md` for the full operating guide.
