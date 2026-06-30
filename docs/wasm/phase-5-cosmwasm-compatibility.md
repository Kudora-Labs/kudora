# Phase 5 CosmWasm Compatibility

This document records the official Wasmd compatibility decision used for Kudora Phase 5.

## Upstream Inspection

- Repository inspected: `https://github.com/CosmWasm/wasmd`
- Temporary inspection path: ignored `tmp/wasmd`
- Latest stable release/tag inspected: `v0.70.3`
- Commit inspected: `47e9cb8aa080eba5db31bc294f614a2e15b3c82e`

## Selected Versions

- Selected Wasmd version: `github.com/CosmWasm/wasmd v0.70.3`
- Selected wasmvm version: `github.com/CosmWasm/wasmvm/v3 v3.0.7`

## Compatibility Evaluation

Upstream `wasmd v0.70.3` declares:

- Cosmos SDK: `v0.54.0`
- CometBFT: `v0.39.0`
- Go: `1.25.9`
- IBC-Go: `v11.1.0`

Current Kudora Phase 4 baseline before Phase 5:

- Cosmos SDK: `v0.54.3`
- CometBFT: `v0.39.3`
- Go baseline: `1.26.4`
- Cosmos EVM: `github.com/cosmos/evm v0.7.0`

Decision:

- `wasmd v0.70.3` is compatible with Kudora's current Cosmos SDK `v0.54.3` and CometBFT `v0.39.3` line.
- Go `1.26.4` remains acceptable for Kudora's active toolchain baseline.
- The only dependency alignment required for the official Wasmd line is the already-upstream-compatible `github.com/cosmos/ibc-go/v11 v11.1.0`.
- A narrow transitive security alignment is also applied:
  - `github.com/shamaton/msgpack/v2 v2.4.1`
  - reason: upstream reviewed advisory `GHSA-h9q6-hc68-35rp` affects `<= 2.4.0`, while the Go vulnerability database still lags on fixed-version metadata
- No new fork exception is required.

## Dependency Policy Check

Allowed for Phase 5:

- official `github.com/CosmWasm/wasmd`
- official `github.com/CosmWasm/wasmvm`
- official CosmWasm transitive dependencies required by `wasmd v0.70.3`

Forbidden and not introduced:

- `replace github.com/CosmWasm/wasmd`
- `replace github.com/CosmWasm/wasmvm`
- `replace github.com/shamaton/msgpack/v2`
- unofficial Wasmd forks
- unofficial wasmvm forks
- Strangelove forks
- Evmos forks
- Rollchains forks
- arbitrary Cosmos SDK or CometBFT forks

## Integration Decision

Phase 5 uses official upstream `github.com/CosmWasm/wasmd v0.70.3` and `github.com/CosmWasm/wasmvm/v3 v3.0.7` as the minimal CosmWasm runtime baseline for Kudora.

This decision preserves:

- the existing Cosmos EVM dependency policy;
- the existing Go baseline `1.26.4`;
- the official Cosmos chain-id `kudora_12000-1`;
- the EVM chain ID `120001`.

## Blocker Status

- Blocker status: none
- Integration can proceed without Wasmd or wasmvm replacements.
