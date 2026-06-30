# Kudora Mainnet Config

This directory contains the reproducible Phase 16 / 16.1 mainnet genesis preparation inputs.

## Files

- `allocations.example.json`: committed example schema with placeholder addresses plus the explicit `genesis_time` / candidate-only fields used by the pipeline.
- `allocations.json`: the active mainnet allocation input for validation. In Phase 16.1 this file is intentionally a candidate/template file that uses two generated public `kudo...` addresses and marks itself as `candidate_only: true`.
- `genesis-policy.md`: Phase 16 policy and validation constraints.
- `gentx/`: public validator gentx drop location. Private keys, node keys, and mnemonics must never be committed here.

## Current Status

Phase 16.1 validates the genesis pipeline with two generated public `kudo...` candidate allocation addresses and the explicit genesis time `2026-08-01T12:00:00Z`.

This keeps the pipeline structurally valid while still marking the resulting genesis as candidate/template only, not launch-ready mainnet. Replace `config/mainnet/allocations.json` with the final public allocation addresses before any real release or launch workflow.

## Required Allocation Arithmetic

- Total supply: `65100000000000000000000000akud` = `65,100,000 KUD`
- Allocation 1: `1310000000000000000000000akud` = `1,310,000 KUD`
- Allocation 2: `5200000000000000000000000akud` = `5,200,000 KUD`
- Community pool: `58590000000000000000000000akud` = `58,590,000 KUD`

## Chain Policy

- Cosmos chain-id: `kudora_12000-1`
- Genesis time policy: `2026-08-01T12:00:00Z` for the current candidate template, with an explicit RFC3339 UTC `Z` suffix required in `allocations.json`
- EVM chain ID: `120001`
- Expected `eth_chainId`: `0x1d4c1`
- Base denom: `akud`
- Display denom: `KUD`
- Decimals: `18`

## Candidate Template Policy

- `candidate_only: true` means the committed allocation file is for validation and packaging only.
- `candidate_reason` must explain why the genesis is not launch-ready.
- A candidate/template genesis may be structurally valid while still being blocked from launch because the allocation wallets are temporary and the public validator gentx set is incomplete.
