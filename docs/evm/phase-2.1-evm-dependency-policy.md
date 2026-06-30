# Phase 2.1 EVM Dependency Policy

Decision: Narrow Cosmos EVM go-ethereum exception approved.

Status note after Phase 3:

- the approved exception is now actively used by Kudora's minimal Cosmos EVM runtime;
- the exception remains narrow and does not authorize any other fork path.

## Default Policy

Kudora's default policy remains no forks.

The only approved exception is the official Cosmos-maintained `go-ethereum` fork required by upstream `github.com/cosmos/evm`.

## Approved Exception

Allowed replacement:

`github.com/ethereum/go-ethereum => github.com/cosmos/go-ethereum v1.17.2-cosmos-0`

Allowed only with:

`github.com/cosmos/evm v0.7.0`

## Approval Conditions

This exception is allowed only if all of the following are true:

1. It is required by upstream official `github.com/cosmos/evm`.
2. The version is exactly the version pinned by the selected upstream Cosmos EVM release.
3. It is documented in this file.
4. It is documented in `docs/release/dependency-baseline.md`.
5. `scripts/verify-no-forks.sh` enforces the exception narrowly.
6. No Kudora-maintained fork is introduced.
7. No local patching of Cosmos EVM or `go-ethereum` is introduced.
8. No arbitrary replacement of `github.com/ethereum/go-ethereum` is allowed.
9. No other fork exception is allowed.

## Current Verified Upstream Basis

Phase 2.1 re-verified:

- upstream repository: `github.com/cosmos/evm`
- inspected tag: `v0.7.0`
- inspected commit: `f4ab9a3e3fbe353468327d5cacda94b33b41ed11`
- upstream replacement still present in both `tmp/cosmos-evm/go.mod` and `tmp/cosmos-evm/evmd/go.mod`
- exact upstream replacement version: `github.com/cosmos/go-ethereum v1.17.2-cosmos-0`

No supported upstream documentation path was found to use `github.com/cosmos/evm v0.7.0` without that replacement.

## Still Forbidden

Forbidden:

- Strangelove forks
- Evmos forks
- Rollchains forks
- unofficial Cosmos SDK forks
- unofficial Cosmos EVM forks
- arbitrary `go-ethereum` replacements
- Kudora-maintained forks
- local patch forks
- any unpinned `go-ethereum` replacement

## Current Kudora Status

Phase 2.1 itself did not add runtime code. That changed later in Phase 3.

Current Kudora runtime status:

- `github.com/cosmos/evm v0.7.0` is now present in Kudora `go.mod`
- the approved `github.com/cosmos/go-ethereum` replacement is now present in Kudora `go.mod`
- EVM runtime is active in the minimal Phase 3 baseline

Active runtime baseline for the next phase:

- official Cosmos chain-id: `kudora_12000-1`
- candidate EVM chain ID: `120001`
- expected `eth_chainId`: `0x1d4c1`
