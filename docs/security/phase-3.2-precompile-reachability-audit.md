# Phase 3.2 Precompile Reachability Audit

## Advisory Metadata

- Advisory ID: `GO-2025-3684` / `GHSA-mjfq-3qr2-6g84`
- Affected module: `github.com/cosmos/evm`
- Kudora dependency version: `github.com/cosmos/evm v0.7.0`
- Public severity: High
- Public impact summary: partial precompile state writes can survive an error path and lead to incorrect balances or nondeterministic execution

Public version metadata currently differs by source:

- GitHub advisory page: affected version shown as `= 0.1.0`, patched versions `None`
- Go vulnerability database / OSV view: all versions affected, no known fixed stable version

For Kudora Phase 3.2, the conservative interpretation is:

- the active upstream stable `v0.7.0` baseline must be treated as affected;
- no stable upstream fixed release is available for automatic adoption in this phase.

## What The Vulnerability Actually Targets

The risky path is not "any EVM call".

It is the Cosmos EVM stateful precompile execution path:

1. a precompile uses Cosmos native state through `RunNativeAction`
2. native state changes are written into the cached multistore
3. an execution error or gas failure happens after a partial write
4. the write is not fully rolled back

In upstream `v0.7.0`, the relevant code path is:

- `precompiles/common/precompile.go`
  - `RunNativeAction`
  - `HandleGasError`
- `x/vm/statedb/journal.go`
  - `precompileCallChange.Revert`
- `x/vm/statedb/statedb.go`
  - `RevertMultiStore`

The GitHub advisory describes the danger directly:

- lower EVM call gas can allow partial precompile execution
- partial writes may remain without a full revert
- distribution reward claiming is a concrete example
- other paths can lead to nondeterministic execution and validator halt

## Why This Is Specifically A Stateful Precompile Problem

The affected upstream patch strategy wraps stateful precompile execution in an atomic rollback path.

The advisory patch introduces:

- an atomic wrapper around precompile execution
- explicit multistore rollback on error
- explicit rollback on out-of-gas during stateful precompile execution

This matters for precompiles that call the Cosmos multistore through `RunNativeAction`, such as:

- staking
- distribution
- bank
- governance
- slashing
- ICS-20
- ICS-02
- ERC20 dynamic/native precompiles
- wrapped ERC20 precompiles

By contrast, plain EVM Prague precompiles, `p256`, and `bech32` do not use that stateful Cosmos precompile path.

## Kudora Phase 3 Runtime Inventory

Kudora does not follow upstream `evmd` defaults for static precompiles.

Upstream `evmd` enables a broad default set that includes:

- staking
- distribution
- ICS-20
- bank
- governance
- slashing
- ICS-02

Kudora intentionally narrows that surface in app wiring and default genesis:

- source wiring uses `kudoraStaticPrecompiles()`
- `kudoraStaticPrecompiles()` includes only:
  - Prague EVM precompiles
  - `p256`
  - `bech32`
- default EVM genesis activates only:
  - `0x0000000000000000000000000000000000000100` (`p256`)
  - `0x0000000000000000000000000000000000000400` (`bech32`)
- default `x/erc20` genesis keeps:
  - `token_pairs = []`
  - `native_precompiles = []`
  - `dynamic_precompiles = []`

## Reachability Decision

For Kudora Phase 3, this advisory is treated as:

`unreachable by active Kudora Phase 3 runtime configuration`

That conclusion is based on the active configuration, not on a local patch.

The conclusion is valid only because all of the following remain true:

1. no stateful Cosmos static precompiles are enabled by default
2. no ERC20 native precompiles are enabled by default
3. no ERC20 dynamic precompiles are enabled by default
4. no token pairs are configured by default
5. Kudora does not switch to the broader upstream `DefaultStaticPrecompiles(...)` set

## Enforcement

The Phase 3.2 waiver is enforced by:

- `scripts/audit-evm-precompile-surface.sh`
- `scripts/assert-evm-precompile-policy.sh`
- `scripts/vulncheck.sh`

If any of those checks fail, the waiver is invalid and the advisory remains a blocker.

## Future Invalidation Rules

This waiver becomes invalid immediately if any future phase does one of the following:

- enables staking, distribution, bank, governance, slashing, ICS-20, or ICS-02 precompiles
- adds ERC20 native precompiles by default
- adds token pairs by default
- adds dynamic ERC20 precompiles by default
- switches Kudora to the upstream broad static precompile registry without a new review

Phase 4 may proceed only if `make phase-3.2-validate` passes under this exact policy.
