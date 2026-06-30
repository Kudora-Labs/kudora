# Phase 14 Docker Explorers

Phase 14 adds Docker-based local explorers for the current Kudora localnet baseline only:

- Blockscout for the EVM runtime
- Ping Dashboard / Ping.pub-style explorer for the Cosmos SDK and CosmWasm runtime

Prerequisite:

```bash
make phase-13.1-validate
```

The explorers attach to the existing localnet and do not replace it.

## Upstream References Inspected

- Blockscout repository commit: `f7039b5e41da2b01dc2b2d33bbbca0ab0be29aff`
- Ping Dashboard repository commit: `f001c4f40256d883c67cfdefdbd5c70414de17c9`

Blockscout is run from official upstream images pinned by digest.
Ping Dashboard is built locally from the inspected upstream commit and embeds the Kudora localnet chain config during the image build.

## Commands

Run from the repository root:

```bash
make docker-build
make localnet-init
make localnet-up
make explorers-up
make explorers-smoke-test
make explorers-logs
make explorers-down
make explorers-reset
make localnet-down
make localnet-reset
make phase-14-validate
```

## Exposed Local URLs

- Blockscout UI and API proxy: `http://localhost:4000`
- Blockscout API base: `http://localhost:4000/api/v2`
- Ping Dashboard UI: `http://localhost:18088`
- Kudora localnet RPC: `http://localhost:26657`
- Kudora localnet REST: `http://localhost:1317`
- Kudora localnet gRPC: `localhost:9090`
- Kudora localnet EVM JSON-RPC: `http://localhost:8545`

## Localnet Target Parameters

- Cosmos chain-id: `kudora_12000-1`
- EVM chain ID: `120001`
- expected `eth_chainId = 0x1d4c1`
- base denom: `akud`
- display denom: `KUD`
- decimals: `18`

## Explorer Behavior

### Blockscout

- connects to Kudora through the shared Docker network alias `kudora-validator-0`
- indexes the localnet EVM chain from `http://kudora-validator-0:8545`
- keeps database and cache state only in local Docker-managed volumes
- exposes the local UI through a small Nginx proxy on port `4000`

### Ping Dashboard

- serves a local-only frontend on port `18088`
- embeds `deploy/explorers/ping-dashboard/config/kudora.json` at build time
- uses browser-reachable localnet endpoints:
  - `http://localhost:1317`
  - `http://localhost:26657`
- joins the localnet Docker network so smoke checks can prove container-to-node reachability as well

## Smoke Coverage

`make explorers-smoke-test` validates:

- Blockscout frontend reachability
- Blockscout API reachability
- Blockscout localnet block indexing
- Ping Dashboard frontend reachability
- Ping Dashboard compiled chain presence for `Kudora Localnet`
- Ping Dashboard container reachability to Kudora RPC and REST endpoints

Phase 14 validation also runs the existing localnet smoke flow before explorer startup, so the explorer stack observes a chain that already has:

- block production
- EVM transfers
- EVM contract interactions
- CosmWasm contract store / instantiate / execute / query activity
- Phase 12 `x/integrity` transactions and encrypted record queries may also be exercised on the same localnet, although the explorers are not required to decode custom module semantics

Phase 15 later adds a separate Docker monitoring stack. Explorer health is still validated by the explorer smoke scripts rather than being treated as a required Prometheus target in the baseline monitoring pass.

## State Policy

- generated localnet state stays under `.localnet/`
- temporary explorer smoke artifacts stay under `tmp/phase-14-*`
- generated explorer databases and caches remain in local Docker-managed volumes only
- no production secrets, mnemonics, validator keys, or node keys are committed

## Not Included Yet

Phase 14 still does not include:

- IBC relayer or product IBC flows
- tokenfactory
- packet-forward
- rate-limit
- ICA
- 08-wasm
- monitoring
- production explorer deployment
- public RPC hardening
- mainnet genesis or release publishing

This explorer stack is localnet-only and is not a production readiness claim.
