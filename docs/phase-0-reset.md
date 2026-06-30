# Phase 0 Reset Baseline

This document records the clean reset of Kudora onto a fresh official Ignite/Cosmos scaffold.

Kudora's official Cosmos chain-id is `kudora_12000-1`. Earlier planning references to `kudora_12000-2` are superseded.

Historical note:

- this document records the reset baseline only;
- later phases may add runtime features on top of that baseline without changing the fact that the reset started from a clean official scaffold.

## Scope

Phase 0 is limited to the reset baseline only.

- No backward compatibility with the legacy network
- No legacy genesis, peers, or network artifacts
- No EVM
- No CosmWasm
- No IBC
- No tokenfactory
- No packet-forward
- No rate-limit
- No ICA
- No 08-wasm
- No explorers
- No Kudora business modules

## Scaffold Command

```bash
ignite scaffold chain github.com/Kudora-Labs/kudora \
  --address-prefix kudo \
  --coin-type 60 \
  --default-denom akud \
  --minimal \
  --no-module \
  --skip-git \
  --path .
```

## Chain Parameters

- Binary name: `kudorad`
- App name: `kudora`
- Go module path: `github.com/Kudora-Labs/kudora`
- Home directory: `.kudora`
- Bech32 account prefix: `kudo`
- Coin type: `60`
- Native base denom: `akud`
- Display denom: `KUD`
- Token decimals: `18`
- Official Cosmos chain-id: `kudora_12000-1`

## Manual Adjustments After Scaffold

Only minimal adjustments were applied after the official Ignite scaffold:

- Replaced the generated repository README with Phase 0 reset documentation.
- Replaced the generated root Makefile with the required Phase 0 commands.
- Replaced the generated `.gitignore` with a public-repo-safe baseline for local homes, artifacts, logs, and secrets.
- Set `sdk.DefaultPowerReduction` to `10^18` to align staking power reduction with the required `18` token decimals.
- Updated the scaffolded local config balances from small placeholder values to `akud` values compatible with `18` decimals.
- Sanitized scaffolded local testnet examples so no concrete private key material is committed.
- Added Phase 0 validation and packaging scripts under `scripts/`.

## Validation

Run the Phase 0 checks with:

```bash
make phase0-validate
make zip
```
