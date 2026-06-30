# Phase 2 EVM Compatibility Matrix

Status note after Phase 3:

- the dependency and app-core alignment described here has now been applied;
- the matrix remains useful as the record of what had to change between the clean Ignite baseline and the minimal Cosmos EVM runtime baseline.

## Baselines

### Kudora

- Go version in `go.mod`: `1.26.4`
- Go version used locally: `go1.26.4`
- Go version in `Dockerfile`: `1.26.4`
- Official Cosmos chain-id baseline: `kudora_12000-1`
- Candidate EVM chain ID for the future runtime phase: `120001`
- Ignite provenance: official `ignite/cli` release tag `v29.10.1`, source hash `d401b9128a7efc2ee642ea733247436368331b41`
- Cosmos SDK: `v0.54.3`
- CometBFT: `v0.39.3`
- Current runtime module set: `auth`, `bank`, `staking`, `distribution`, `genutil`, `consensus`, `authz`, `feegrant`, `upgrade`, `evidence`, `vm`, `feemarket`, `erc20`
- Current replace directives:
  - `github.com/bytedance/sonic => github.com/bytedance/sonic v1.15.0`
  - `github.com/gin-gonic/gin => github.com/gin-gonic/gin v1.9.1`
  - `github.com/syndtr/goleveldb => github.com/syndtr/goleveldb v1.0.1-0.20210819022825-2ae1ddf74ef7`
  - `nhooyr.io/websocket => github.com/coder/websocket v1.8.7`
  - `github.com/ethereum/go-ethereum => github.com/cosmos/go-ethereum v1.17.2-cosmos-0`

### Upstream Cosmos EVM Inspected

- Repository: `https://github.com/cosmos/evm`
- Latest stable tag inspected: `v0.7.0`
- Commit inspected: `f4ab9a3e3fbe353468327d5cacda94b33b41ed11`
- Root module path: `github.com/cosmos/evm`
- `evmd` module path: `github.com/cosmos/evm/evmd`
- Go version in root `go.mod`: `1.25.9`
- Cosmos SDK: `v0.54.3`
- CometBFT: `v0.39.3`
- `go-ethereum` dependency: `github.com/ethereum/go-ethereum v1.16.8`
- Root replace directives include:
  - `github.com/ethereum/go-ethereum => github.com/cosmos/go-ethereum v1.17.2-cosmos-0`
  - `github.com/99designs/keyring => github.com/cosmos/keyring v1.2.0`
  - `github.com/tidwall/btree => github.com/cosmos/btree ...`
- Local Phase 2 compile check: `go test ./... -run '^$'` passed in `tmp/cosmos-evm/evmd`
- EVM modules present:
  - `x/vm`
  - `x/feemarket`
  - `x/erc20`
- Additional EVM surfaces present:
  - JSON-RPC server
  - EVM mempool
  - precompile registry
  - Ethereum keyring and signing support

## Matrix

| Topic | Kudora | Cosmos EVM `v0.7.0` | Classification | Notes |
| --- | --- | --- | --- | --- |
| Go version baseline | `go 1.26.4`, local/Docker `1.26.4` | `go 1.25.9` | Compatible | Kudora now validates on a newer but compatible Go baseline, and the previously planned alignment has been applied. |
| Ignite path | Standard Ignite scaffold | No first-class core Ignite scaffold for EVM | Unknown / needs manual review | EVM exists as an official Ignite app, not as a core scaffold mode. |
| Cosmos SDK | `v0.54.3` | `v0.54.3` | Compatible | The required SDK alignment is now applied. |
| CometBFT | `v0.39.3` | `v0.39.3` | Compatible | The required CometBFT alignment is now applied. |
| `go-ethereum` path | Approved upstream replacement in use | Replaced upstream with `github.com/cosmos/go-ethereum` | Compatible | Kudora now uses the exact approved Phase 2.1 exception. |
| Core app shape | Upstream-aligned explicit `baseapp` wiring | Custom `evmd` example app with explicit EVM wiring | Compatible | Kudora now follows the upstream `evmd` pattern closely. |
| EVM modules | `x/vm`, `x/feemarket`, `x/erc20` wired | `x/vm`, `x/feemarket`, `x/erc20` | Compatible | Phase 3 delivers the minimal runtime wiring. |
| Ante handler | Cosmos EVM ante chain | Cosmos EVM ante chain | Compatible | Kudora now uses upstream-aligned EVM ante handling. |
| Mempool | Cosmos EVM priority/nonce mempool | Cosmos EVM priority/nonce mempool | Compatible | Comet `mempool.type = "app"` is part of the working baseline. |
| JSON-RPC server | Present but disabled by default | Present | Compatible | Phase 3 validation enables it only for the local smoke path. |
| EVM chain ID handling | Not applicable yet | Explicit `evm-chain-id` config/flag | Compatible | Upstream `evmd` uses an explicit numeric EVM chain ID, which matches Kudora policy better than the Ignite app's hash-based approach. |
| Precompile framework | Not present | Static precompile registry present | Unknown / needs manual review | Upstream default set includes non-EVM surfaces such as IBC-related precompiles that Kudora has not approved yet. |
| ERC-20/native denom bridge | Not present | `x/erc20` present | Requires major dependency alignment | Needs careful alignment with Kudora's `akud` / `KUD` 18-decimal model. |

## Ignite EVM App Addendum

The official Ignite EVM app was also reviewed as a separate path candidate.

| Topic | Ignite EVM app | Classification | Notes |
| --- | --- | --- | --- |
| Official status | Present in official `ignite/apps` repo | Compatible | It is official and maintained by the Ignite ecosystem. |
| Local tests | `go test ./...` passed in `tmp/ignite-apps/evm` | Compatible | The app's own integration test passed locally. |
| Cosmos EVM target | `github.com/cosmos/evm v0.6.0` | Requires minor dependency alignment | Behind upstream `v0.7.0`. |
| `go-ethereum` replacement | Adds `github.com/cosmos/go-ethereum v1.16.2-cosmos-1` | Blocked | Still outside Kudora's approved exception, which only covers `github.com/cosmos/evm v0.7.0` with `github.com/cosmos/go-ethereum v1.17.2-cosmos-0`. |
| EVM chain ID strategy | FNV hash of Cosmos chain ID | Blocked | Violates Kudora's explicit chain ID requirement. |
| App discovery in local validated environment | `ignite app list` / `ignite appregistry list` failed | Blocked | App registry build currently fails locally. |

## Compatibility Summary

- The official Ignite EVM app exists and is tested, but it is not acceptable for Kudora as-is.
- The upstream `evmd` reference was the right official design source and is now the implemented Phase 3 baseline.
- The Phase 2.1 exception is now actively used and remains tightly constrained.
- The minimal EVM runtime is active in Kudora, while broader protocol and operational phases remain out of scope.
- The active Kudora Cosmos chain baseline is `kudora_12000-1`, and the explicit Phase 3 EVM chain ID is `120001`.
