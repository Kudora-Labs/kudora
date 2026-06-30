# Kudora

Kudora is being rebuilt from a clean official Ignite/Cosmos baseline. Phase 0 reset the repository, Phase 0.1 hardened the baseline, Phase 1 added the first Docker and CI layer, Phase 2 selected the official Cosmos EVM path, Phase 2.1 approved the narrow upstream `go-ethereum` dependency exception, Phase 3 integrated the minimal upstream-aligned Cosmos EVM runtime, Phase 3.2 closed the Cosmos EVM precompile reachability blocker, Phase 4 validated EVM transactions and contracts, Phase 5 added a minimal official CosmWasm runtime, Phase 5.1 closed the validation-integrity gap for the CosmWasm baseline, Phase 12 added the first business module `x/integrity`, Phase 12.1-lite added two-step tenant ownership transfer for that module, Phase 13 added a complete contributor-focused Docker localnet for the current Cosmos + EVM + CosmWasm runtime, Phase 13.1 hardened that localnet for Docker-first portability, Phase 14 added local-only Docker explorers for the same validated runtime, Phase 15 added a local-only Docker monitoring stack, Phase 16 / 16.1 prepare and validate the reproducible mainnet genesis pipeline in explicit candidate/template mode, and Phase 17 adds a candidate/devnet release pipeline plus a local Cosmovisor runtime.

Kudora's official Cosmos chain-id is `kudora_12000-1`. Earlier planning references to `kudora_12000-2` are superseded.

The current repository state preserves these chain parameters:

- Binary name: `kudorad`
- App name: `kudora`
- Home directory: `.kudora`
- Address prefix: `kudo`
- Coin type: `60`
- Base denom: `akud`
- Display denom: `KUD`
- Token decimals: `18`
- Phase 3 EVM chain ID candidate in use for runtime validation: `120001`
- Expected JSON-RPC `eth_chainId`: `0x1d4c1`

## Current Runtime Scope

The current repository baseline includes:

- upstream `github.com/cosmos/evm v0.7.0`
- the approved replacement `github.com/ethereum/go-ethereum => github.com/cosmos/go-ethereum v1.17.2-cosmos-0`
- minimal EVM runtime wiring for:
  - `x/vm`
  - `x/feemarket`
  - `x/erc20`
- upstream `github.com/CosmWasm/wasmd v0.70.3`
- upstream `github.com/CosmWasm/wasmvm/v3 v3.0.7`
- minimal CosmWasm runtime wiring for:
  - `x/wasm`
- the first Kudora business module:
  - `x/integrity`
- conservative default Wasm permissions:
  - code upload: `Nobody`
  - instantiate default permission: `Nobody`

`x/integrity` is a generic encrypted data integrity layer. It supports tenant registration, two-step tenant ownership transfer, immutable encrypted set commitments, full-set queries, and single-record-by-tag queries. The module recalculates a deterministic Merkle root on-chain but never decrypts ciphertext and never stores plaintext business fields.

JSON-RPC remains disabled by default in config. The local validation flow enables it explicitly during smoke tests.

Kudora does not patch Cosmos EVM or CosmWasm locally. The narrow Phase 3.2 waiver for `GO-2025-3684` remains valid only while Kudora keeps all stateful Cosmos precompiles and default ERC20 precompile surfaces inactive.

The repository now includes local-only smoke tests for:

- EVM account funding
- `eth_getBalance`
- `eth_getTransactionCount`
- `eth_sendRawTransaction`
- `eth_getTransactionReceipt`
- EVM nonce progression
- EVM gas accounting
- minimal contract deployment
- `eth_call` readback
- contract state update verification
- CosmWasm store / instantiate / execute / query validation

These tests run either against temporary single-node homes under `tmp/` or against the Docker localnet under `.localnet/`, and they do not claim mainnet readiness. The default localnet init path is now Docker-first, while host-assisted init remains an explicit debugging mode only.

## Mainnet Genesis Preparation

Phase 16 / 16.1 add a deterministic mainnet-genesis preparation pipeline for the current Kudora baseline:

- chain-id `kudora_12000-1`
- base denom `akud`
- display denom `KUD`
- decimals `18`
- EVM chain ID `120001`
- expected `eth_chainId` `0x1d4c1`
- total supply `65100000000000000000000000akud` = `65,100,000 KUD`
- allocation 1 `1310000000000000000000000akud` = `1,310,000 KUD`
- allocation 2 `5200000000000000000000000akud` = `5,200,000 KUD`
- community pool `58590000000000000000000000akud` = `58,590,000 KUD`

The repository now carries a committed `config/mainnet/allocations.json` candidate file with two generated public `kudo...` addresses, explicit `genesis_time = 2026-08-01T12:00:00Z`, and `candidate_only: true`. This allows full structural validation while still marking the result as template-only and not final launch-ready mainnet.

Standard Cosmos SDK governance remains stake-based. Validators vote with their own bonded stake and delegated stake unless delegators vote directly, and delegators may override validator votes depending on standard governance behavior. Phase 16 does not introduce validator-only governance.

## Intentionally Not Included Yet

This repository still intentionally excludes:

- any business module other than `x/integrity`
- production IBC app wiring and relayer flows
- tokenfactory
- packet-forward
- rate-limit
- ICA
- 08-wasm
- production explorer deployment and public explorer hardening; Phase 14 adds localnet-only explorers
- production mainnet genesis and operational rollout assets

No production secrets, validator keys, node keys, mnemonics, private keys, `.env` files, or credentials are included in this repository.

## Candidate Release Scope

Phase 17 defines the first candidate release as:

- release version `v0.1.0-rc.1`
- release track `candidate`
- release type `devnet_candidate`
- mainnet launch-ready `false`

This candidate release is intentionally not a final mainnet release. The
candidate genesis remains structurally valid, but the committed allocation
addresses are temporary candidate public addresses and real validator gentx
files are still required before launch readiness can become true.

## Validation Commands

```bash
make build
make test
make lint
make verify-no-forks
make verify-clean-reset
make verify-no-secrets
make dependency-audit
make audit-evm-precompile-surface
make assert-evm-precompile-policy
make vulncheck
make docker-build
make docker-smoke-test
make localnet-init
make localnet-up
make localnet-smoke-test
make integrity-smoke-test
make monitoring-up
make monitoring-smoke-test
make monitoring-down
make monitoring-reset
make mainnet-genesis-build
make mainnet-genesis-validate
make mainnet-genesis-inspect-supply
make mainnet-genesis-inspect-policy
make phase-16-validate
make release-build-binaries
make release-package
make release-verify
make release-docker-build
make release-docker-verify
make cosmovisor-image-build
make cosmovisor-layout-verify
make cosmovisor-smoke-test
make phase-17-validate
make explorers-up
make explorers-smoke-test
make explorers-down
make explorers-reset
make localnet-down
make localnet-reset
make phase-13.1-validate
make phase-14-validate
make phase-12-validate
make phase-12.1-lite-validate
make phase-15-validate
make evm-smoke-test
make evm-transaction-smoke-test
make evm-contract-smoke-test
make wasm-smoke-test
make phase-3-validate
make phase-3.2-validate
make phase-4-validate
make phase-5-validate
make phase-5.1-validate
make phase-13-validate
make zip
```

## Reference Documents

- `docs/phase-0-reset.md`
- `docs/docker/phase-1-docker.md`
- `docs/docker/phase-13-localnet.md`
- `docs/docker/phase-13.1-localnet-portability.md`
- `docs/docker/phase-14-explorers.md`
- `docs/docker/phase-15-monitoring.md`
- `docs/mainnet/phase-16-genesis.md`
- `docs/release/phase-17-candidate-release-cosmovisor.md`
- `docs/modules/phase-12-integrity.md`
- `docs/modules/phase-12.1-lite-integrity-ownership-transfer.md`
- `docs/evm/phase-2-official-evm-path.md`
- `docs/evm/phase-2-evm-compatibility-matrix.md`
- `docs/evm/phase-2-evm-integration-design.md`
- `docs/evm/phase-2.1-evm-dependency-policy.md`
- `docs/evm/phase-3-evm-runtime.md`
- `docs/evm/phase-4-evm-functional-validation.md`
- `docs/wasm/phase-5-cosmwasm-compatibility.md`
- `docs/wasm/phase-5-cosmwasm-runtime.md`
- `docs/security/phase-3.1-vulnerability-audit.md`
- `docs/security/phase-3.2-precompile-reachability-audit.md`
- `docs/security/phase-5-cosmwasm-vulnerability-audit.md`
- `docs/release/dependency-baseline.md`

Kudora now has minimal EVM and CosmWasm runtime support, the generic `x/integrity` business module MVP with transferable tenant ownership, local functional validation, a Docker localnet, local-only explorers, local-only monitoring, a mainnet-genesis preparation pipeline, and a candidate/devnet release plus Cosmovisor packaging layer. This is still not a mainnet-readiness claim: Phase 16 / 16.1 distinguish a structurally valid genesis template from a launch-ready mainnet artifact, and Phase 17 keeps `mainnet_launch_ready=false` while the repository still uses candidate allocation wallets and no real validator gentx set.
