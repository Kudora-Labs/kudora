# Phase 16: Mainnet Genesis Preparation

Phase 16 prepares a reproducible Kudora mainnet genesis pipeline without adding any new protocol modules.
Phase 16.1 finalizes that pipeline in candidate/template mode with two generated public `kudo...` allocation addresses so the structural validation flow can be completed before the final production wallets are provided.

## Fixed Chain Parameters

- Cosmos chain-id: `kudora_12000-1`
- Candidate genesis time: `2026-08-01T12:00:00Z`
- Base denom: `akud`
- Display denom: `KUD`
- Decimals: `18`
- EVM chain ID: `120001`
- Expected `eth_chainId`: `0x1d4c1`

## Supply Plan

- Total supply: `65100000000000000000000000akud` = `65,100,000 KUD`
- Allocation 1: `1310000000000000000000000akud` = `1,310,000 KUD`
- Allocation 2: `5200000000000000000000000akud` = `5,200,000 KUD`
- Community pool: `58590000000000000000000000akud` = `58,590,000 KUD`

## Community Pool Encoding

Kudora follows the Cosmos SDK `x/distribution` model:

- `app_state.distribution.fee_pool.community_pool` stores the pool as `DecCoins`.
- The distribution module account also holds the same amount as a bank balance.
- Bank supply remains exactly equal to the total supply after allocations and community pool funding.

## Governance Caveat

Standard Cosmos SDK governance voting power is stake-based. Validators vote with their own bonded stake and delegated stake unless delegators vote directly. Delegators may override validator votes depending on standard governance behavior.

Phase 16 does not implement validator-only governance or any custom governance behavior.

## Runtime Preservation

- CosmWasm upload permission remains `Nobody`.
- CosmWasm instantiate default permission remains `Nobody`.
- EVM denom remains `akud`.
- EVM chain ID remains `120001`.
- `x/integrity` genesis remains empty.
- `x/integrity` still uses the MVP tenant model with permissionless registration plus explicit ownership transfer support.
- Registrar- or governance-controlled tenant registration is still future work.

## Files And Commands

- `config/mainnet/allocations.example.json`: committed schema with placeholders and explicit candidate/template fields.
- `config/mainnet/allocations.json`: current candidate/template allocation file with two generated public `kudo...` addresses.
- `scripts/mainnet/build-genesis.sh`: builds the genesis template from the active allocation file.
- `scripts/mainnet/validate-genesis.sh`: validates arithmetic, policy, and temporary node startup behavior.
- `scripts/mainnet/inspect-genesis-supply.sh`: prints exact supply arithmetic.
- `scripts/mainnet/inspect-genesis-policy.sh`: validates policy constraints.
- `make mainnet-genesis-build`
- `make mainnet-genesis-validate`
- `make mainnet-genesis-inspect-supply`
- `make mainnet-genesis-inspect-policy`
- `make phase-16-validate`
- `make phase-16.1-validate`

## Candidate Allocation Status

The current committed `config/mainnet/allocations.json` is intentionally marked `candidate_only: true` because it uses two generated public `kudo...` addresses for pipeline validation. The final production allocation wallets must replace these addresses before any launch-ready mainnet artifact can exist.

Phase 17 consumes this exact candidate/template state to build a
candidate/devnet release. That downstream release remains explicitly
non-mainnet-ready and inherits the same `candidate_only: true` limitation.

## Launch-Ready Versus Template-Valid

- `genesis_template_valid: PASS` means the file structure, arithmetic, community pool encoding, EVM baseline, Wasm defaults, and `x/integrity` defaults are valid.
- `mainnet_launch_ready: FAIL` in the current Phase 16.1 flow means the committed allocation wallets are candidate/template only and real public validator gentx files are still missing.
- The temporary node startup check uses an ignored runtime copy under `tmp/mainnet-genesis/runtime/` and rewrites only that local validation copy to a recent past `genesis_time`. The committed/output candidate genesis artifact keeps the explicit `2026-08-01T12:00:00Z` timestamp unchanged.

No private keys, node keys, mnemonics, or generated local homes are committed in Phase 16 / 16.1.
