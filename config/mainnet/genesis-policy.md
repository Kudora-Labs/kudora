# Kudora Mainnet Genesis Policy

## Chain Baseline

- Cosmos chain-id: `kudora_12000-1`
- Genesis time must be explicit in `config/mainnet/allocations.json` and must use RFC3339 UTC with a `Z` suffix.
- EVM chain ID: `120001`
- Expected `eth_chainId`: `0x1d4c1`
- Base denom: `akud`
- Display denom: `KUD`
- Decimals: `18`

## Supply Policy

- Total supply must be exactly `65100000000000000000000000akud`.
- Allocation 1 must be exactly `1310000000000000000000000akud`.
- Allocation 2 must be exactly `5200000000000000000000000akud`.
- Community pool must be exactly `58590000000000000000000000akud`.
- Allocation 1 + Allocation 2 + Community pool must equal the total supply exactly.

## Community Pool Encoding

Phase 16 uses the standard Cosmos SDK `x/distribution` fee pool representation:

- `app_state.distribution.fee_pool.community_pool` stores the community pool as `DecCoins`.
- The distribution module account must also hold the same integer `akud` amount in `app_state.bank.balances`.
- Bank supply must remain exactly `65100000000000000000000000akud`.

## Governance Caveat

Standard Cosmos SDK governance voting power is stake-based. Validators vote with their own bonded stake and delegated stake unless delegators vote directly. Delegators may override validator votes depending on standard governance behavior.

Phase 16 does not implement validator-only governance, custom governance weighting, or project-funding governance rules.

## Runtime Policy

- CosmWasm defaults must remain conservative: upload `Nobody`, instantiate `Nobody`.
- EVM runtime must keep `akud` as the EVM denom.
- `x/integrity` genesis must remain empty by default.
- No registrar- or governance-based tenant registration changes are added in this phase.

## Candidate Allocation Policy

- Phase 16.1 currently commits a candidate/template `allocations.json` with two generated public `kudo...` addresses.
- Candidate files must set `candidate_only: true` and provide a non-empty `candidate_reason`.
- Candidate/template allocations are valid for structural genesis validation only. They are not final launch-ready mainnet wallets.

## Launch Readiness Policy

- A genesis template may be structurally valid before public validator gentx files are supplied.
- A template that still uses candidate-only allocation wallets is **not** launch-ready.
- A template without real public gentx files is **not** launch-ready.
- Public gentx files may be committed only if they contain no private key material.
- Temporary startup validation may rewrite only the ignored runtime copy under `tmp/mainnet-genesis/runtime/` to a recent past `genesis_time`; the committed candidate genesis artifact must keep its configured explicit timestamp unchanged.
