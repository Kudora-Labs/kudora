# Phase 12.1-lite Integrity Ownership Transfer

Phase 12.1-lite keeps the Phase 12 tenant registration model intentionally simple for the MVP:

- tenant names are globally unique;
- registration remains first-come-first-served;
- the registration signer becomes the tenant owner;
- only the current tenant owner may commit integrity sets.

This phase adds only one new capability: safe two-step ownership transfer.

## Scope

The scope is intentionally narrow:

- add `pending_owner` to tenant state;
- add two-step ownership transfer messages;
- preserve immutable integrity-set commits;
- preserve the generic encrypted-record design;
- avoid registrar, governance, freeze, or namespace-reservation logic.

Future hardening remains out of scope for this phase:

- registrar-controlled registration;
- governance-controlled registration;
- namespace reservations;
- freeze or unfreeze controls;
- DNS or domain-proof ownership claims.

## Ignite Scaffold Commands Used

The ownership-transfer extension was scaffold-first. The following Ignite commands were used in a disposable scaffold workspace and then refined into the current repository:

```bash
ignite scaffold module integrity --dep bank -p <temporary-scaffold-dir> -y
ignite scaffold message transfer-tenant-ownership tenant new-owner --module integrity -p <temporary-scaffold-dir> -y
ignite scaffold message accept-tenant-ownership tenant --module integrity -p <temporary-scaffold-dir> -y
ignite scaffold message cancel-tenant-ownership-transfer tenant --module integrity -p <temporary-scaffold-dir> -y
```

## Manual Deviations From Scaffold

Minimal manual refinement was still required:

- Kudora does not keep Ignite injection hooks in-repo, so the scaffold had to be generated in a temporary chain and applied back into the current app wiring.
- The existing `Tenant` proto had to be extended carefully with append-only field numbering to preserve wire compatibility for already-generated structures.
- Keeper validation was tightened so ownership transfer remains explicit, address-normalized, and deterministic.
- The integrity smoke flow was extended manually because the ownership-transfer scenario spans multiple transactions and two different accounts.

## Ownership Model

Tenant ownership is now:

- `owner`: the current tenant owner;
- `pending_owner`: the account that has been nominated by the current owner but has not yet accepted.

The transfer is two-step:

1. current owner starts the transfer;
2. pending owner accepts the transfer.

The owner may also cancel a pending transfer before acceptance.

## Messages

### `MsgTransferTenantOwnership`

Rules:

- signer must be the current tenant owner;
- tenant must already exist;
- `new_owner` must be a valid Bech32 account address;
- `new_owner` must not equal the current owner;
- the message sets `pending_owner`;
- the message does not immediately change `owner`.

### `MsgAcceptTenantOwnership`

Rules:

- signer must equal `pending_owner`;
- tenant must already exist;
- `owner` becomes the signer;
- `pending_owner` is cleared.

### `MsgCancelTenantOwnershipTransfer`

Rules:

- signer must be the current tenant owner;
- tenant must already exist;
- `pending_owner` must be present;
- `pending_owner` is cleared.

## Commit Behavior During Transfer

The integrity commit rule remains simple:

- only `owner` may commit integrity sets.

That means:

- the pending owner cannot commit before accepting;
- the current owner can still commit while the transfer is pending;
- the old owner cannot commit after the pending owner accepts;
- the new owner can commit after acceptance.

## CLI

The module now exposes:

```bash
kudorad tx integrity transfer-tenant-ownership [tenant] [new-owner]
kudorad tx integrity accept-tenant-ownership [tenant]
kudorad tx integrity cancel-tenant-ownership-transfer [tenant]
```

The existing generic queries continue to expose tenant ownership state, including `pending_owner`.

## Local Smoke Coverage

The ownership transfer flow is validated by:

```bash
make integrity-smoke-test
make phase-12.1-lite-validate
```

The smoke test covers:

- register tenant with owner A;
- owner A commits an encrypted integrity set;
- owner A starts a transfer to owner B;
- owner B is rejected before acceptance;
- owner A can still commit while the transfer is pending;
- owner B accepts ownership;
- owner A is rejected after acceptance;
- owner B commits a new integrity set;
- full-set and record-by-tag queries remain correct;
- no plaintext Orbitrum-like scoring data is returned.

## Orbitrum Example Boundary

Orbitrum remains only a documentation and test example.

The module itself stays business-agnostic:

- no Orbitrum-specific fields are stored on-chain;
- no scoring-specific plaintext is stored on-chain;
- Kudora only stores encrypted `tag`, `nonce`, and `ciphertext`;
- Kudora never decrypts the payload.
