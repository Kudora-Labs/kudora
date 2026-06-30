# Phase 13 Docker Localnet

Phase 13 adds a complete Docker localnet for the current Kudora runtime baseline only:

- Cosmos SDK chain
- Cosmos EVM JSON-RPC
- CosmWasm runtime
- the later Phase 12 `x/integrity` business-module smoke flow can also reuse the same localnet

It does not add any future protocol modules or production operational scope.

## Localnet Scope

The localnet is intentionally limited to:

- one validator service: `kudora-validator-0`
- chain-id `kudora_12000-1`
- EVM chain ID `120001`
- expected `eth_chainId = 0x1d4c1`
- local-only state under `.localnet/`
- local-only smoke artifacts under `tmp/localnet/`

Not included in Phase 13 itself:

- IBC relayer or transfer product flows
- tokenfactory
- packet-forward
- rate-limit
- ICA
- 08-wasm
- explorers inside the Phase 13 baseline itself; Phase 14 adds them as an optional local-only layer
- monitoring
- production validator hardening
- mainnet genesis

## Commands

Run from the repository root:

```bash
make localnet-init
make docker-build
make localnet-up
make localnet-smoke-test
make integrity-smoke-test
make localnet-logs
make localnet-down
make localnet-reset
make phase-13-validate
```

Phase 13.1 hardens the localnet so the default init path is Docker-first. On a clean contributor machine, `make localnet-init` now uses the local Docker image instead of requiring a host `build/kudorad` binary.

Optional host-assisted mode remains available for debugging only:

```bash
KUDORA_LOCALNET_INIT_MODE=host make localnet-init
```

## Exposed Endpoints

- CometBFT P2P: `26656`
- CometBFT RPC: `26657`
- CometBFT Prometheus metrics: `26660`
- Cosmos REST API: `1317`
- Cosmos gRPC: `9090`
- EVM JSON-RPC HTTP: `8545`
- EVM JSON-RPC WebSocket: `8546`

## State And Key Policy

- Generated localnet state is written only to `.localnet/`.
- Temporary smoke results are written only to `tmp/localnet/`.
- No localnet state, validator keys, node keys, or temporary EVM keys may be committed.
- The localnet uses generated local-only keys rather than committed deterministic secrets.
- The localnet genesis is structurally reproducible, but the generated local-only keys remain intentionally non-committed.

## Portability Notes

- The Docker Compose service runs with a fixed non-root runtime user (`65532:65532`) and the Docker-first init flow generates localnet state with matching ownership semantics.
- The stable local Docker network name is `kudora-localnet`.
- The localnet still requires host-side tools for the reusable smoke scripts, but the init path itself is Docker-first.
- See `docs/docker/phase-13.1-localnet-portability.md` for the full portability model.

## Smoke Coverage

`make localnet-smoke-test` validates:

- CometBFT RPC health and strict block production growth
- REST API health
- gRPC reachability
- `eth_chainId`
- `eth_blockNumber`
- EVM read-only smoke
- EVM value-transfer smoke
- EVM contract smoke
- CosmWasm store / instantiate / execute / query smoke

Phase 12 adds a separate `make integrity-smoke-test` flow that reuses the same localnet in existing-node mode to validate tenant registration, encrypted set commitment, full-set queries, and record-by-tag queries for `x/integrity`.

The smoke flow reuses the repository smoke scripts in existing-node mode instead of spinning a second temporary node.
Each smoke run deletes its prior `tmp/localnet/phase-13-smoke` directory before execution and writes a current-run result artifact with block-height delta metadata.

Phase 15 later attaches Prometheus and Grafana to the same Docker network and scrapes the CometBFT metrics endpoint exposed on `26660`.

## CosmWasm Localnet Policy

Committed default Wasm permissions remain conservative (`Nobody` / `Nobody`).

For the localnet only, `deploy/localnet/scripts/init-localnet.sh` patches the generated local genesis inside `.localnet/` so a local-only uploader account can run the CosmWasm smoke contract. This patch is not committed to the repository runtime baseline.

## Security Notes

- This localnet is for contributors and integrators, not for public RPC exposure.
- Docker images are built locally only and are not pushed to a registry.
- The localnet does not weaken the Phase 3.2 EVM precompile waiver.
- No stateful Cosmos EVM precompiles, ERC20 token pairs, or ERC20 native precompiles are enabled by default.
