# Phase 4 EVM Functional Validation

Phase 4 proves that Kudora's minimal Cosmos EVM runtime is functionally usable beyond read-only JSON-RPC checks while preserving the Phase 3.2 precompile waiver. Phase 5 keeps these EVM assertions active while adding a separate minimal CosmWasm runtime.

## Scope

Phase 4 validates:

- EVM account funding
- `eth_chainId`
- `eth_getBalance`
- `eth_getTransactionCount`
- `eth_sendRawTransaction`
- `eth_getTransactionReceipt`
- EVM nonce progression
- EVM gas accounting
- minimal contract deployment
- `eth_call`
- contract state update and readback

Phase 4 does not add new runtime modules, business logic, or protocol surfaces.

## Test Account Strategy

The smoke tests use temporary, local-only ECDSA accounts generated at runtime under ignored `tmp/` directories.

Properties of this strategy:

- no mnemonic is committed
- no validator or node key is reused
- no `.env` file is involved
- private key material stays under `tmp/`
- scripts print only public addresses, transaction hashes, and contract addresses

Each generated EVM address is funded through genesis by converting the same public key bytes into the Kudora bech32 account address form.

## Transaction Smoke Test

Command:

```bash
make evm-transaction-smoke-test
```

The transaction smoke test:

1. creates a temporary single-node home under `tmp/phase-4-evm-tx-smoke`
2. initializes `kudora_12000-1` with base denom `akud`
3. generates local sender and recipient EVM accounts
4. funds the sender in genesis
5. enables JSON-RPC locally
6. waits for `eth_chainId = 0x1d4c1`
7. waits for the first block through `eth_blockNumber`
8. reads the funded sender balance and nonce
9. sends a signed EVM value transfer
10. waits for the transaction receipt
11. asserts `receipt.status == 0x1`
12. asserts sender nonce progression
13. asserts recipient balance increase
14. asserts non-zero `gasUsed`

## Contract Smoke Test

Command:

```bash
make evm-contract-smoke-test
```

The contract smoke test:

1. creates a temporary single-node home under `tmp/phase-4-evm-contract-smoke`
2. generates and funds a local deployer account
3. deploys a minimal storage contract from committed test-only bytecode
4. waits for the deployment receipt
5. asserts `receipt.status == 0x1`
6. asserts the `contractAddress` is present
7. reads the initial storage value with `eth_call`
8. sends a signed `store(uint256)` transaction
9. waits for the state-changing receipt
10. asserts `receipt.status == 0x1`
11. reads storage again and verifies the updated value

The contract bytecode is committed as a test-only asset under `testutil/evm-smoke/` so the validation flow does not require a Solidity compiler, Foundry, or any external RPC.

## Receipt, Gas, Nonce, And Logs

Phase 4 validates:

- successful receipts for transfer, deployment, and state change
- non-zero `gasUsed` on successful EVM transactions
- nonce progression for the sending/deploying account
- JSON-RPC correctness for read and write flows

The chosen minimal storage contract does not emit events. Phase 4 therefore records receipt log counts but does not claim semantic event/log validation yet.

## Security And Precompile Waiver

Phase 4 preserves the Phase 3.2 waiver conditions:

- no stateful Cosmos static precompiles are enabled by default
- no ERC20 native precompiles are enabled by default
- no ERC20 dynamic precompiles are enabled by default
- no token pairs are configured by default
- the active static precompile surface remains limited to Prague, `p256`, and `bech32`

Phase 4 keeps passing:

```bash
make audit-evm-precompile-surface
make assert-evm-precompile-policy
make vulncheck
```

If a future phase enables stateful Cosmos precompiles or ERC20 default precompile surfaces, the Phase 3.2 waiver becomes invalid and must be re-evaluated.

## Validation Entry Point

Command:

```bash
make phase-4-validate
```

This full validation gate runs the Phase 3.2 baseline first, then the Phase 4 transaction and contract smoke paths, then regenerates the inspection archive.

## Intentionally Not Included Yet

Phase 4 still does not add:

- IBC transfer product flows
- packet-forward
- rate-limit
- ICA
- 08-wasm
- tokenfactory
- business modules
- explorers
- monitoring
- mainnet genesis
- release publishing
- public mainnet readiness claims

Phase 5 later layers official `x/wasm` runtime support on top of this EVM baseline, but it does not relax any of the EVM-side receipt, gas, nonce, or precompile-waiver checks documented here.

Phase 13 reuses these same EVM smoke scripts in an existing-node mode so a running Docker localnet can be validated without spinning a second temporary single-node chain. Phase 14 then reuses the same localnet activity so Blockscout can observe indexed EVM blocks and transactions against the running chain.
