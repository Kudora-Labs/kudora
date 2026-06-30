# Phase 2 EVM Integration Design

Status note after Phase 3:

- the minimal implementation described here has now been landed;
- this document remains useful as the design rationale for the chosen shape and constraints.

## Decision

Chosen path for the future EVM implementation phase:

- design source: upstream `github.com/cosmos/evm` `evmd` reference implementation;
- implementation status today: minimal runtime active in Kudora after Phase 3;
- dependency policy status: Phase 3 is unblocked only under the approved narrow exception documented in `docs/evm/phase-2.1-evm-dependency-policy.md`;
- reason: this is the most official upstream reference and the only approved fork exception is the upstream Cosmos-maintained `github.com/cosmos/go-ethereum` replacement pinned by `github.com/cosmos/evm v0.7.0`.

Do not use the Ignite EVM app as Kudora's implementation source.

Active baseline note:

- Kudora's official Cosmos chain-id is `kudora_12000-1`.
- Earlier planning references to `kudora_12000-2` are superseded.

## Target Scope For The First EVM Runtime Phase

The first actual EVM integration phase was intentionally kept minimal and focused on official Cosmos EVM runtime components:

- `x/vm`
- `x/feemarket`
- `x/erc20`

No business modules should be introduced during the first EVM wiring cut.

## Files Likely To Change In The Actual EVM Phase

Actual Kudora touch points, based on the upstream `evmd` structure and the Phase 3 implementation:

- `go.mod`
- `go.sum`
- `app/app.go`
- `app/app_config.go`
- `app/config.go`
- `app/genesis.go`
- `cmd/kudorad/cmd/root.go`
- command wiring files under `cmd/kudorad/cmd/`
- dedicated EVM support files such as:
  - `app/mempool.go`
  - `app/tx_verifier.go`
- later operational files:
  - `Dockerfile`
  - docs and validation scripts

If the future implementation requires touching many additional Cosmos core files beyond this set, that is a warning sign that the integration is drifting into custom-core maintenance.

## Expected Runtime Changes

### EVM ante handler

Expected direction:

- replace the plain Ignite ante chain with the Cosmos EVM ante flow;
- use upstream patterns equivalent to `evmante.NewAnteHandler(...)`;
- include dynamic fee handling, EVM transaction extension option checks, and fee market integration.

Rule:

- do not invent a Kudora-specific ante stack when upstream `evmd` already defines the behavior.

### EVM mempool

Expected direction:

- adopt the upstream Cosmos EVM mempool model for nonce ordering and price replacement semantics;
- align with upstream proposal, insert, reap, and check-tx handler wiring;
- avoid partial adoption.

Rule:

- if the EVM mempool cannot be adopted in an upstream-aligned way, pause the implementation rather than landing a hybrid custom mempool.

### JSON-RPC configuration

Expected direction:

- adopt upstream Cosmos EVM server/config patterns for JSON-RPC;
- keep JSON-RPC disabled by default initially;
- bind locally by default during early validation;
- enable ports later only when explicitly configured.

Later Docker port strategy:

- `8545` JSON-RPC HTTP
- `8546` WebSocket only if explicitly enabled

Phase 3 exposes those ports in Docker while still keeping JSON-RPC disabled by default in the runtime config.

### EVM keyring and signing

Expected direction:

- keep Kudora bech32 prefix `kudo`;
- keep coin type `60`;
- use Ethereum secp256k1 keyring/signing behavior where required by Cosmos EVM;
- keep Ledger expectations aligned with coin type `60` and the Ethereum app when Ledger support is added.

Rule:

- do not compromise the existing `kudo` address prefix just to mirror `evmd` defaults.

## EVM Chain ID Strategy

Kudora must use an explicit numeric EVM chain ID.

Mandatory rule:

- do not derive the EVM chain ID from the Cosmos chain ID by hashing or by any implicit transform.

Proposed candidate for review only:

- `120001`

Rationale:

- stable numeric mapping from `kudora_12000-1`;
- easy to document and reason about;
- close enough to the Cosmos chain identity to stay recognizable.

Expected JSON-RPC representation:

- `0x1d4c1`

Status:

- active for the Phase 3 validation baseline;
- still subject to later mainnet governance and ecosystem coordination before final production lock-in.

## Native Denom Strategy

Kudora should keep a single native gas and staking denomination:

- base denom: `akud`
- display denom: `KUD`
- decimals: `18`

Rule:

- no dual-denom workaround;
- no separate EVM gas denom;
- no hidden decimal translation layer.

## 18-Decimal Strategy

The EVM integration phase must preserve Kudora's intended 18-decimal token design end to end:

- bank metadata must expose `KUD` with exponent `18`;
- genesis balances and validator bond amounts must be expressed consistently at 18-decimal scale;
- EVM runtime, fee market, and ERC-20 bridging assumptions must all align with that single canonical precision.

## Precompile Strategy

Kudora should not create custom precompiles in the first EVM wiring phase.

However, upstream `evmd` includes a broader default static precompile surface than Kudora has approved, including IBC-related precompiles and middleware.

Phase 2 design rule:

- use upstream precompile architecture as the reference;
- do not approve automatic inclusion of non-EVM scope items merely because `evmd` contains them;
- if upstream components cannot be cleanly limited to the approved scope, stop and re-evaluate before merging.

This is one of the main reasons the future implementation phase needs a careful diff review against upstream `evmd`.

## Validation Strategy For The Future EVM Phase

Minimum validation bar for the first actual EVM wiring phase:

- `make tidy`
- `make build`
- `make test`
- `make lint`
- `make verify-no-forks`
- `make verify-clean-reset`
- `make verify-no-secrets`
- `make docker-build`
- `make docker-smoke-test`
- `make evm-smoke-test`
- `ignite chain build --check-dependencies`

Additional EVM-specific checks expected later:

- `kudorad version --long`
- `kudorad start --help` shows EVM flags
- EVM modules appear in query/help output
- JSON-RPC disabled by default unless explicitly enabled
- local smoke test for `8545` once JSON-RPC is introduced
- explicit validation of chain ID, denom metadata, and keyring behavior

Dependency policy gate for that phase:

- the only approved `go-ethereum` replacement is `github.com/ethereum/go-ethereum => github.com/cosmos/go-ethereum v1.17.2-cosmos-0`;
- it is allowed only together with `github.com/cosmos/evm v0.7.0`;
- any other fork path remains forbidden.

## Rollback Strategy

If the future EVM implementation phase reveals any of the following, rollback instead of merging:

- Kudora would need to maintain a long-lived custom patch stack on Cosmos core;
- official upstream requires a fork path that Kudora policy does not approve;
- the integration cannot be kept close to upstream `evmd`;
- unsupported IBC or other excluded feature surfaces become mandatory side effects;
- the EVM chain ID strategy cannot remain explicit and stable.

Rollback method:

- revert the EVM wiring commit stack;
- keep Phase 2 documentation and validation assets;
- resume from the clean non-EVM baseline.
