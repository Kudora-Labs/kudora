# Dependency Baseline

This document records Kudora's active dependency baseline after the Phase 3 EVM runtime integration, the Phase 3.2 precompile reachability closure, the Phase 4 EVM functional validation pass, the Phase 5 minimal CosmWasm runtime integration, the Phase 12 `x/integrity` business module MVP, the Phase 12.1-lite tenant ownership transfer extension, the later Docker localnet/explorer/monitoring layers through Phase 15, the Phase 16 mainnet-genesis preparation pipeline, and the Phase 17 candidate release plus Cosmovisor runtime tooling.

## Toolchain

- Go version baseline: `1.26.4`
- Go version from `go.mod`: `1.26.4`
- Go version used locally during Phase 3.2 validation: `go1.26.4`
- Docker build Go version: `1.26.4`
- GitHub Actions Go version: explicit `1.26.4`
- Ignite provenance: official `ignite/cli` release tag `v29.10.1`, validated in Phase 0.1 by source hash `d401b9128a7efc2ee642ea733247436368331b41`

## Active Chain Baseline

- Official Cosmos chain-id: `kudora_12000-1`
- Earlier planning chain-id `kudora_12000-2` is superseded
- Active Phase 3 EVM chain ID for runtime validation: `120001`
- Expected JSON-RPC `eth_chainId`: `0x1d4c1`

## Core Dependencies

- Cosmos SDK: `v0.54.3`
- CometBFT: `v0.39.3`
- Cosmos EVM: `v0.7.0`
- Wasmd: `v0.70.3`
- wasmvm: `v3.0.7`
- IBC-Go: `v11.1.0`
- `go-ethereum` required by Cosmos EVM: `v1.17.0`

## Replace Directives

Current `go.mod` replace directives:

1. `github.com/bytedance/sonic => github.com/bytedance/sonic v1.15.0`
   Status: allowed, temporary compatibility-related
   Reason: keeps the dependency graph compatible with the current Go toolchain.

2. `github.com/gin-gonic/gin => github.com/gin-gonic/gin v1.9.1`
   Status: allowed, temporary security-related
   Reason: preserves the upstream mitigation for a known vulnerability.

3. `github.com/syndtr/goleveldb => github.com/syndtr/goleveldb v1.0.1-0.20210819022825-2ae1ddf74ef7`
   Status: allowed, temporary compatibility-related
   Reason: preserves the upstream workaround for the broken module resolution path.

4. `nhooyr.io/websocket => github.com/coder/websocket v1.8.7`
   Status: allowed, temporary compatibility-related
   Reason: preserves the upstream workaround for the broken vanity import path.

5. `github.com/ethereum/go-ethereum => github.com/cosmos/go-ethereum v1.17.2-cosmos-0`
   Status: allowed, approved Phase 2.1 Cosmos EVM policy exception
   Reason: required by official upstream `github.com/cosmos/evm v0.7.0` and enforced narrowly by `scripts/verify-no-forks.sh`.

No replace directive is allowed for:

- `github.com/CosmWasm/wasmd`
- `github.com/CosmWasm/wasmvm`

## Cosmos EVM Dependency Policy

Kudora keeps a strict no-fork policy by default.

The only approved exception is:

- `github.com/ethereum/go-ethereum => github.com/cosmos/go-ethereum v1.17.2-cosmos-0`

Allowed only with:

- `github.com/cosmos/evm v0.7.0`

This exception is approved only because:

- it is required by upstream official `github.com/cosmos/evm`;
- Kudora does not maintain a local fork of Cosmos EVM or `go-ethereum`;
- the replacement version is pinned exactly;
- `scripts/verify-no-forks.sh` rejects any other `go-ethereum` replacement or version.

## Forbidden Runtime Forks

The following remain forbidden:

- Strangelove Cosmos SDK or Cosmos EVM forks
- Evmos Cosmos SDK or `go-ethereum` forks
- Rollchains Wasmd fork
- unofficial Wasmd forks
- unofficial wasmvm forks
- unofficial Cosmos SDK forks
- unofficial Cosmos EVM forks
- arbitrary `go-ethereum` replacements
- Kudora-maintained Cosmos core forks
- local patch forks for Cosmos EVM or `go-ethereum`

## CosmWasm Security Alignment

Phase 5 introduces one transitive security alignment inside the official CosmWasm dependency graph:

- `github.com/shamaton/msgpack/v2 v2.4.1`

Reason:

- the official upstream CosmWasm runtime graph pulls `msgpack` transitively through `wasmvm`;
- GitHub's reviewed advisory `GHSA-h9q6-hc68-35rp` marks `github.com/shamaton/msgpack/v2 <= 2.4.0` as affected;
- the Go vulnerability database still reports stale `all versions, no known fixed` metadata for `GO-2026-4513`, plus duplicate `GO-2026-4740`.

Kudora does not add a replace directive, fork, or local patch for this remediation. The policy is documented in `docs/security/phase-5-cosmwasm-vulnerability-audit.md`.

## Current Runtime Status

Phase 3 activates the minimal Cosmos EVM runtime in Kudora. Phase 4 adds test-only functional validation helpers. Phase 5 adds the minimal official CosmWasm runtime without introducing a second fork exception.

Active runtime scope:

- `x/vm`
- `x/feemarket`
- `x/erc20`
- `x/wasm`
- Cosmos EVM ante handling
- Cosmos EVM mempool
- JSON-RPC server wiring
- conservative CosmWasm permission defaults:
  - code upload `Nobody`
  - instantiate default permission `Nobody`

Phase 4 and Phase 5 validation helpers:

- use the already-approved upstream `go-ethereum` dependency surface that comes with `github.com/cosmos/evm v0.7.0`
- add no new fork exception
- add only the official upstream `github.com/CosmWasm/wasmd` / `github.com/CosmWasm/wasmvm` runtime surface
- keep contract bytecode and signing logic under `testutil/evm-smoke/` as test-only assets
- keep the CosmWasm test contract artifact under `testutil/wasm/` as a committed test-only asset with documented provenance and hash

Not included yet:

- any business module other than `x/integrity`
- production IBC feature rollout
- tokenfactory
- packet-forward
- rate-limit
- ICA
- 08-wasm
- production explorers; Phase 14 adds Docker explorer infrastructure without changing the Go dependency baseline
- mainnet launch-ready genesis

## Phase 15 Monitoring Baseline

Phase 15 adds:

- Prometheus
- blackbox-exporter
- Grafana

These are Docker-only localnet services. They do not change the Go module graph and do not introduce any new fork exception or runtime core dependency.

## Phase 16 / 16.1 Genesis Preparation Baseline

Phase 16 / 16.1 add:

- `config/mainnet/` allocation and policy inputs
- `scripts/mainnet/` genesis build, validation, supply-inspection, and policy-inspection tooling
- `docs/mainnet/phase-16-genesis.md`

These assets do not change the Go dependency graph, do not introduce any new fork exception, and do not add any new protocol module. They only validate that the current runtime baseline can be encoded into a deterministic mainnet genesis template with:

- chain-id `kudora_12000-1`
- explicit candidate genesis time `2026-08-01T12:00:00Z`
- base denom `akud`
- display denom `KUD`
- decimals `18`
- EVM chain ID `120001`
- conservative Wasm defaults (`Nobody` / `Nobody`)
- empty default `x/integrity` genesis
- exact supply `65100000000000000000000000akud`
- exact community pool `58590000000000000000000000akud`
- candidate-only public allocation addresses until the final production wallets are supplied

## Phase 17 Candidate Release Tooling

Phase 17 adds:

- `VERSION = 0.1.0-rc.1`
- committed candidate release metadata under `release/`
- local candidate release packaging scripts under `scripts/release/`
- a local candidate Cosmovisor runtime under `deploy/cosmovisor/`

These assets do not change the application module graph and do not add any new
protocol module. The only new external tool used during Phase 17 packaging is
the official `cosmossdk.io/tools/cosmovisor` binary, pinned in the local build
scripts to `v1.6.0`.

## IBC Dependency Status

`github.com/cosmos/ibc-go/v11` appears in the dependency graph because:

- upstream Cosmos EVM `v0.7.0` expects IBC core keeper integration in its broader architecture; and
- upstream Wasmd `v0.70.3` depends on IBC core interfaces even when Kudora keeps IBC product flows inactive.

Current Kudora status in Phase 5:

- IBC core keeper dependency exists
- IBC transfer product flow is not active
- no transfer module wiring is enabled in Kudora app code
- no relayer configuration is included
- no packet-forward middleware is included
- no rate-limit middleware is included
- no ICA flow is included
- no 08-wasm light client module is wired into the app
- no channel or operational IBC rollout artifacts are included
- no Wasm IBC product message/query surface is enabled for contracts

This is an inactive/non-product IBC dependency state, not an IBC product launch.

## Phase 3.2 Vulnerability Waiver Policy

`GO-2025-3684` / `GHSA-mjfq-3qr2-6g84` remains a known upstream advisory against `github.com/cosmos/evm`.

Kudora does not patch Cosmos EVM locally.

Instead, Phase 3.2 allows a narrow configuration-based waiver only while all of the following remain true:

- no stateful Cosmos static precompiles are enabled by default
- no ERC20 native precompiles are enabled by default
- no ERC20 dynamic precompiles are enabled by default
- no token pairs are configured by default
- the active runtime keeps the static precompile surface limited to Prague, `p256`, and `bech32`

If any future phase activates stateful Cosmos precompiles or ERC20 default precompile surfaces, the Phase 3.2 waiver becomes invalid and the advisory must be re-evaluated.

## Validation Implications

`scripts/verify-no-forks.sh` enforces:

- `github.com/cosmos/evm` must be exactly `v0.7.0`
- the only allowed `go-ethereum` replacement is `github.com/cosmos/go-ethereum v1.17.2-cosmos-0`
- any other `go-ethereum` replacement fails
- any `replace github.com/CosmWasm/wasmd` or `replace github.com/CosmWasm/wasmvm` fails
- any Strangelove, Evmos, Rollchains, unofficial Cosmos SDK, unofficial Cosmos EVM, or unofficial Wasmd path fails

`scripts/vulncheck.sh` now enforces:

- `GO-2025-3684` is waivable only if the Phase 3.2 reachability proof still passes
- any unrelated high/critical finding still fails the build
- any unmapped severity finding fails pending manual review

Phase 4 extends the validation surface with:

- `make evm-transaction-smoke-test` for funding, balance, nonce, receipt, and gas assertions
- `make evm-contract-smoke-test` for deployment, `eth_call`, and contract state update assertions
- `make phase-4-validate` as the full regression gate on top of Phase 3.2

Phase 5 extends the validation surface with:

- `make wasm-smoke-test` for store / instantiate / execute / query coverage against a temporary local node
- `make phase-5-validate` as the full regression gate on top of Phase 4

## Business Module Baseline

Phase 12 introduces the first Kudora business module:

- `x/integrity`

`x/integrity` does not introduce a new fork exception and does not alter the chain dependency baseline materially beyond the standard Ignite/Cosmos module surface already present in the repo.

Its scope is intentionally generic:

- tenant ownership registry
- immutable encrypted set commitments
- deterministic canonicalization and Merkle root verification
- full-set and single-record queries

It does not add:

- Orbitrum-specific production code
- scoring-specific production code
- plaintext business data storage
- custom Cosmos core forks
- protocol-module expansion beyond the current Cosmos + EVM + CosmWasm baseline
