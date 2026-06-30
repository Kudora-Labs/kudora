# Phase 5 CosmWasm Runtime

Phase 5 adds a minimal official CosmWasm runtime to Kudora while preserving the Phase 4 EVM validation baseline and the Phase 3.2 EVM precompile waiver.

Phase 5.1 tightens validation integrity around this runtime by ensuring the Phase 4 and Phase 5 reports consume only current-run smoke artifacts and do not reuse stale `tmp/` result files as proof.

Phase 13 reuses the same runtime baseline in a Docker localnet and keeps the committed Wasm permissions conservative by applying any local uploader permission patch only inside ignored localnet state.

## What Was Integrated

- official `github.com/CosmWasm/wasmd v0.70.3`
- official `github.com/CosmWasm/wasmvm/v3 v3.0.7`
- minimal `x/wasm` app wiring
- Wasm CLI wiring under `kudorad tx wasm ...` and `kudorad query wasm ...`
- Wasm snapshot support
- Wasm-aware ante handling for Cosmos transactions

The runtime stays close to upstream Wasmd patterns and does not introduce a local `x/wasm` fork or custom Wasm keeper copy.

## Conservative Permission Policy

Committed default genesis policy for Phase 5:

- code upload permission: `Nobody`
- instantiate default permission: `Nobody`

This is intentionally conservative and closer to a mainnet-safe default than permissionless upload.

For the local smoke test only, genesis is patched inside ignored `tmp/phase-5-wasm-smoke/` to allow a single temporary uploader address to store and instantiate a test contract. That temporary patch is not committed.

For the Docker localnet only, `deploy/localnet/scripts/init-localnet.sh` applies the same kind of temporary local-only uploader permission patch inside `.localnet/validator0/config/genesis.json`.

## Contract Smoke Test Strategy

Command:

```bash
make wasm-smoke-test
```

The smoke test:

1. creates a temporary home under `tmp/phase-5-wasm-smoke`
2. initializes `kudora_12000-1` with base denom `akud`
3. preserves EVM chain ID `120001`
4. starts a single local node
5. verifies `eth_chainId = 0x1d4c1` still holds
6. stores a deterministic test-only CosmWasm contract
7. instantiates it
8. executes a state update
9. queries state back
10. stops the node cleanly

## Contract Artifact Provenance

- Committed artifact: `testutil/wasm/reflect_1_5.wasm`
- Provenance: copied from official upstream Wasmd keeper testdata
- Upstream source path used during inspection: `tmp/wasmd/x/wasm/keeper/testdata/reflect_1_5.wasm`
- SHA256: `45de7a3ac8a72368a71c813d6b0cf7024f8b3581ffa1fc8d2c5fd4060f950c01`

The validation flow checks this hash before using the artifact.

## EVM Preservation

Phase 5 must not regress EVM behavior. The full validation chain still runs:

```bash
make evm-smoke-test
make evm-transaction-smoke-test
make evm-contract-smoke-test
```

This preserves:

- `eth_chainId = 0x1d4c1`
- EVM value transfer validation
- nonce progression validation
- receipt and gas accounting validation
- minimal EVM contract deployment and `eth_call`

## EVM Precompile Waiver Preservation

Phase 5 does not activate:

- stateful Cosmos static precompiles
- ERC20 native precompiles by default
- ERC20 dynamic precompiles by default
- ERC20 token pairs by default

The Phase 3.2 waiver for `GO-2025-3684` remains valid only because the active EVM precompile surface stays limited to Prague, `p256`, and `bech32`.

## IBC And Wasm Scope Boundaries

Although Wasmd depends on IBC core interfaces, Phase 5 does not activate:

- IBC transfer product flows
- packet-forward
- rate-limit
- ICA
- 08-wasm light clients
- relayer flows

Contract-facing Wasm IBC message/query surfaces are disabled in Kudora's Wasm keeper options for this phase.

## Docker Considerations

The Docker image remains:

- multi-stage
- non-root
- free of node homes and secrets

`CGO_ENABLED=1` stays enabled because Kudora now depends on both the Cosmos EVM cgo path and `wasmvm`.

Phase 5 does not add any new network ports. CosmWasm execution shares the chain process and standard Cosmos APIs.

Phase 13 adds Docker Compose orchestration around the same image and exposes the existing Cosmos and EVM ports for local-only use. Phase 14 then layers local-only Docker explorers on top of the same runtime without changing the Wasm module set or permission defaults.

## Intentionally Not Included Yet

Phase 5 still does not add:

- business modules
- IBC transfer product rollout
- tokenfactory
- packet-forward
- rate-limit
- ICA
- 08-wasm light clients
- production explorer deployment; Phase 14 adds local-only explorer containers only
- monitoring
- mainnet genesis
- release publishing

This is a runtime baseline, not a mainnet-readiness claim.
