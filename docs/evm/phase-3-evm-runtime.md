# Phase 3 EVM Runtime

Kudora's official Cosmos chain-id is `kudora_12000-1`. Earlier planning references to `kudora_12000-2` are superseded.

## Scope Delivered

Phase 3 integrates the minimal upstream-aligned Cosmos EVM runtime into Kudora. Phase 3.2 closes the upstream precompile reachability blocker without patching Cosmos EVM locally. Phase 4 keeps the runtime surface unchanged and adds functional transaction and contract validation on top of it.

Implemented baseline:

- upstream reference: `github.com/cosmos/evm`
- integrated release tag: `v0.7.0`
- verified upstream commit: `f4ab9a3e3fbe353468327d5cacda94b33b41ed11`
- approved dependency exception in use:
  - `github.com/ethereum/go-ethereum => github.com/cosmos/go-ethereum v1.17.2-cosmos-0`

## Runtime Modules Wired

The Kudora app now wires:

- `x/vm`
- `x/feemarket`
- `x/erc20`
- Cosmos EVM ante handling
- Cosmos EVM mempool handling
- JSON-RPC server wiring

The implementation follows the upstream `evmd` structure closely while keeping Kudora-specific changes limited to chain parameters, token metadata, and configuration defaults.

## Current Precompile Surface

Kudora does not enable the full upstream `evmd` static precompile set.

Kudora currently activates:

- the upstream Prague EVM precompiles
- the upstream `p256` precompile
- the upstream `bech32` precompile

Kudora does not activate the following stateful Cosmos static precompiles by default:

- staking
- distribution
- bank
- governance
- slashing
- ICS-20
- ICS-02

The default `x/erc20` genesis also keeps:

- `token_pairs = []`
- `native_precompiles = []`
- `dynamic_precompiles = []`

This narrow surface is enforced by Phase 3.2 validation because the upstream advisory `GO-2025-3684` is relevant specifically to stateful precompile execution.

## Dependency Alignment

Phase 3 aligns Kudora to the dependency baseline required by upstream Cosmos EVM `v0.7.0`:

- Cosmos SDK: `v0.54.3`
- CometBFT: `v0.39.3`
- Cosmos EVM: `v0.7.0`
- IBC-Go runtime dependency: `v11.0.0`

No unofficial forks were added.

The only approved fork exception remains:

- `github.com/ethereum/go-ethereum => github.com/cosmos/go-ethereum v1.17.2-cosmos-0`

Known upstream advisory state:

- `GO-2025-3684` / `GHSA-mjfq-3qr2-6g84` remains a known upstream advisory against `github.com/cosmos/evm`
- Kudora does not patch Cosmos EVM locally
- Phase 3.2 waives the advisory only because the vulnerable stateful precompile surface is unreachable in Kudora's active runtime configuration

## Chain And Token Strategy

Active Phase 3 runtime values:

- Cosmos chain-id: `kudora_12000-1`
- EVM chain ID: `120001`
- expected JSON-RPC `eth_chainId`: `0x1d4c1`

Token strategy preserved:

- base denom: `akud`
- display denom: `KUD`
- decimals: `18`
- power reduction: `10^18`

The Phase 3 runtime keeps a single native denom and does not introduce a second EVM gas token.

## Init And Genesis Behavior

Kudora now uses a custom `init` command wrapper so the generated genesis baseline includes the required Kudora defaults from the first write:

- `akud` bank metadata with `KUD` display denomination
- staking bond denom `akud`
- mint denom `akud`
- EVM denom `akud`
- EVM static precompile activation list
- fee market `no_base_fee = true`
- CometBFT `mempool.type = "app"` for Cosmos EVM mempool compatibility

## JSON-RPC Configuration

JSON-RPC support is now wired into the binary.

Current defaults:

- HTTP JSON-RPC address: `127.0.0.1:8545`
- WebSocket JSON-RPC address: `127.0.0.1:8546`
- JSON-RPC disabled by default until explicitly enabled

Security note:

- the repository does not claim that public mainnet JSON-RPC exposure is production-ready;
- Phase 3 validation only proves local runtime correctness for a controlled single-node smoke path.
- the local Docker validation image tag used after Phase 3.2 is `kudora/kudorad:phase3-local`.

## Docker Changes

The base Docker image now exposes:

- `26656`
- `26657`
- `1317`
- `9090`
- `8545`
- `8546`

The image still runs as non-root and still excludes local homes, secrets, `.env` files, node keys, and validator keys.

## Smoke Test

The local EVM smoke test is:

```bash
make evm-smoke-test
```

It performs:

1. temporary local home creation under `tmp/phase-3-evm-smoke`
2. single-node init with `kudora_12000-1`
3. local key generation with ignored files only
4. genesis funding and self-delegation in `akud`
5. node start with JSON-RPC enabled locally
6. `eth_chainId` assertion for `0x1d4c1`
7. `eth_blockNumber` assertion after first block
8. `eth_getBalance` assertion for the funded local validator account
9. `net_version` or `web3_clientVersion` sanity check

## Phase 4 Functional Validation

Phase 4 adds local-only smoke paths for signed EVM transactions and contract execution without enabling any new protocol modules or precompile surfaces.

Additional commands:

```bash
make evm-transaction-smoke-test
make evm-contract-smoke-test
make phase-4-validate
```

The transaction smoke path validates:

1. temporary ECDSA account generation under `tmp/phase-4-evm-tx-smoke`
2. genesis funding in `akud`
3. `eth_chainId`
4. `eth_getBalance`
5. `eth_getTransactionCount`
6. a signed value transfer through `eth_sendRawTransaction`
7. `eth_getTransactionReceipt`
8. sender nonce progression
9. recipient balance increase
10. non-zero `gasUsed`

The contract smoke path validates:

1. temporary ECDSA deployer generation under `tmp/phase-4-evm-contract-smoke`
2. deployment of a minimal storage contract from committed test-only bytecode
3. deployment receipt success and non-zero gas usage
4. `eth_call` readback of the initial stored value
5. a signed state-changing `store(uint256)` transaction
6. receipt success and nonce progression for the state-changing call
7. `eth_call` readback of the updated stored value

The chosen minimal contract does not emit events, so Phase 4 records receipt log counts but does not claim event semantic validation yet.

## Intentionally Not Included Yet

Phase 3 and Phase 4 do not add:

- business modules
- production IBC app features beyond the minimal keeper dependency needed by the upstream Cosmos EVM ante path
- CosmWasm
- tokenfactory
- packet-forward
- rate-limit
- ICA
- 08-wasm
- explorers
- monitoring
- mainnet genesis
- stateful Cosmos precompile activation
- ERC20 token pair defaults
- ERC20 native precompile defaults

## IBC Dependency Status

The app carries an IBC core keeper dependency because upstream Cosmos EVM `v0.7.0` expects that keeper surface in its broader architecture.

Current Phase 3.2 status remains non-product IBC:

- no transfer module rollout
- no relayer
- no channels
- no packet-forward
- no rate-limit
- no ICA
- no explorer or operational IBC tooling

Phase 4 does not change this status. The functional validation helpers exercise only the EVM JSON-RPC surface and a single-node local consensus path.

## Known Risks And Follow-Up

Phase 3 proves the minimal runtime path, but it is not the final mainnet operating model.

Follow-up work is still needed for:

- operational hardening of JSON-RPC exposure
- explicit precompile surface review
- advisory re-evaluation if any future phase activates stateful Cosmos precompiles
- localnet and rehearsal flows
- broader event/log coverage and more advanced contract scenarios
- later protocol additions such as IBC and CosmWasm
- business modules
