# Phase 12 Integrity Module

Phase 12 adds Kudora's first business module: `x/integrity`.

The module is business-agnostic. It stores encrypted record commitments for a tenant, dataset type, and period. Kudora validates ownership, canonicalization, and Merkle integrity, but it never decrypts payloads and never stores plaintext business fields on-chain.

Orbitrum expert scoring history is only an example client payload used in test-only helpers and docs. Production module code does not know about Orbitrum, experts, projects, scores, or any scoring schema.

## Goal

`x/integrity` supports four generic capabilities:

1. Register a tenant namespace and owner.
2. Transfer tenant ownership through a two-step pending-owner flow.
3. Commit an immutable encrypted record set for `tenant / type / period`.
4. Query either the full committed set or one record by tag.

## Ignite Scaffold-First Approach

Phase 12 used Ignite CLI as the starting point for the module skeleton, message/query surfaces, proto package layout, and keeper/module boilerplate.

In-place scaffold attempt:

```bash
ignite scaffold module integrity --dep bank -p .
```

The current Kudora app is manually wired and does not expose the standard Ignite injection hooks, so the scaffold could not be applied in-place safely.

Reusable scaffold sequence used in a disposable temporary chain:

```bash
ignite scaffold chain github.com/Kudora-Labs/kudora \
  --address-prefix kudo \
  --coin-type 60 \
  --default-denom akud \
  --no-module \
  --skip-git \
  -p <temporary-scaffold-dir>

ignite scaffold module integrity --dep bank -p <temporary-scaffold-dir> -y
ignite scaffold type integrity-record tag nonce ciphertext --module integrity --no-message -p <temporary-scaffold-dir> -y
ignite scaffold message register-tenant tenant --module integrity -p <temporary-scaffold-dir> -y
ignite scaffold message commit-integrity-set tenant dataset-type period root --module integrity -p <temporary-scaffold-dir> -y
ignite scaffold message transfer-tenant-ownership tenant new-owner --module integrity -p <temporary-scaffold-dir> -y
ignite scaffold message accept-tenant-ownership tenant --module integrity -p <temporary-scaffold-dir> -y
ignite scaffold message cancel-tenant-ownership-transfer tenant --module integrity -p <temporary-scaffold-dir> -y
ignite scaffold query tenant tenant --module integrity -p <temporary-scaffold-dir> -y
ignite scaffold query integrity-set tenant dataset-type period --module integrity -p <temporary-scaffold-dir> -y
ignite scaffold query integrity-record tenant dataset-type period tag --module integrity -p <temporary-scaffold-dir> -y
```

## Manual Deviations From Scaffold

Only the parts that Ignite could not express cleanly were refined by hand:

- Kudora's current app and CLI wiring are manual, so the scaffold output had to be connected into `app/app.go` and `cmd/kudorad/cmd/commands.go`.
- Ignite scaffold could not express a field literally named `type`, so the scaffolded `dataset_type` field was refined to `type`.
- The repeated `records []IntegrityRecord` payload plus the richer full-set and single-record query responses required manual proto refinement.
- The runtime command tree does not consume AutoCLI directly, so explicit CLI commands were added under `x/integrity/client/cli`.
- The two-step ownership-transfer behavior required manual keeper validation around `owner` and `pending_owner`.

## Messages

### `MsgRegisterTenant`

Fields:

- `creator`
- `tenant`

Rules:

- `tenant` must be valid and normalized
- tenant must not already exist
- creator becomes owner
- emits `tenant_registered`

### `MsgCommitIntegritySet`

Fields:

- `creator`
- `tenant`
- `type`
- `period`
- `root`
- `records []IntegrityRecord`

Rules:

- tenant must exist
- creator must be tenant owner
- `tenant / type / period` is immutable and cannot be overwritten
- records must be non-empty
- records may arrive unsorted
- records are normalized and sorted by `tag` before hashing and storage
- duplicate tags are rejected
- the keeper recalculates the Merkle root from the normalized records
- the submitted root must match exactly
- emits `integrity_set_committed`

### `MsgTransferTenantOwnership`

Fields:

- `creator`
- `tenant`
- `new_owner`

Rules:

- signer must be the current tenant owner
- tenant must exist
- `new_owner` must be a valid address
- `new_owner` must differ from the current owner
- the message sets `pending_owner` only
- the owner changes only after explicit acceptance

### `MsgAcceptTenantOwnership`

Fields:

- `creator`
- `tenant`

Rules:

- signer must equal `pending_owner`
- tenant must exist
- a transfer must be pending
- `owner` becomes the signer
- `pending_owner` is cleared

### `MsgCancelTenantOwnershipTransfer`

Fields:

- `creator`
- `tenant`

Rules:

- signer must be the current tenant owner
- tenant must exist
- a transfer must be pending
- `pending_owner` is cleared

## Generic Types

### `Tenant`

- `tenant`
- `owner`
- `created_height`
- `created_time`
- `pending_owner`

### `IntegritySet`

- `tenant`
- `type`
- `period`
- `root`
- `creator`
- `block_height`
- `block_time`
- `record_count`

### `IntegrityRecord`

- `tag`
- `nonce`
- `ciphertext`

## Validation Limits

Typed limits are defined in `x/integrity/types/keys.go`:

- `MaxTenantLength = 64`
- `MaxTypeLength = 128`
- `MaxPeriodLength = 64`
- `MaxRecordsPerSet = 1024`
- `MaxNonceBytes = 64`
- `MaxCiphertextBytes = 32768`
- `MaxTotalCiphertextBytes = 4194304`

Validation rules:

- `tenant`: lower-case, `a-z 0-9 . _ -`, max 64
- `type`: lower-case normalized, `a-z 0-9 . _ - :`, max 128
- `period`: generic string, non-empty, max 64, no control characters
- `root`: `0x` prefixed 32-byte lowercase hex
- `tag`: `0x` prefixed 32-byte lowercase hex, unique within a set
- `nonce`: `0x` prefixed even-length hex, non-empty, max 64 bytes
- `ciphertext`: `0x` prefixed even-length hex, non-empty, bounded per record and per set

## Canonical Record JSON

Leaf canonicalization is deterministic and exactly:

```json
{"tag":"<tag>","nonce":"<nonce>","ciphertext":"<ciphertext>"}
```

Field order is fixed:

1. `tag`
2. `nonce`
3. `ciphertext`

Hex fields are normalized to lowercase before hashing and before storage.

## Merkle Root Algorithm

1. Validate records.
2. Normalize `tag`, `nonce`, and `ciphertext`.
3. Sort records by `tag` ascending.
4. Compute `leafHash = SHA256(canonical_leaf_json)`.
5. Build the Merkle tree from leaf hashes.
6. Duplicate the last node on any odd-sized level.
7. Compute each parent as `SHA256(left || right)`.
8. Encode the final root as lowercase `0x` hex.

A one-record tree root is the single leaf hash.

## Storage Model

Deterministic store collections are used for:

- `tenant/{tenant}`
- `set/{tenant}/{type}/{period}`
- `record/{tenant}/{type}/{period}/{tag}`

The store contains only:

- tenant ownership metadata
- integrity set metadata
- sorted encrypted records

No plaintext business attributes are stored.

## Mainnet Genesis Preservation

Phase 16 keeps `x/integrity` conservative at genesis time:

- no pre-registered tenants
- no preloaded integrity sets
- no registrar-controlled tenant bootstrap
- no governance-controlled tenant bootstrap

The module still starts from an empty default genesis and relies on runtime tenant registration plus explicit ownership transfer flows.

## Queries

The module exposes:

- `query integrity tenant [tenant]`
- `query integrity set [tenant] [type] [period]`
- `query integrity record [tenant] [type] [period] [tag]`

The full-set query returns metadata plus sorted records.
The record query returns metadata plus a single encrypted record.
The tenant query returns both `owner` and `pending_owner`.

## CLI / gRPC / REST

Phase 12 wires:

- `tx integrity register-tenant`
- `tx integrity transfer-tenant-ownership`
- `tx integrity accept-tenant-ownership`
- `tx integrity cancel-tenant-ownership-transfer`
- `tx integrity commit-set`
- `query integrity tenant`
- `query integrity set`
- `query integrity record`
- gRPC query services
- gRPC-Gateway REST handlers generated from the module proto package

## Events

Emitted events intentionally avoid leaking encrypted payload material:

### `tenant_registered`

- `tenant`
- `owner`

### `integrity_set_committed`

- `tenant`
- `type`
- `period`
- `root`
- `creator`
- `record_count`

### `tenant_ownership_transfer_started`

- `tenant`
- `owner`
- `pending_owner`

### `tenant_ownership_transferred`

- `tenant`
- `previous_owner`
- `owner`

### `tenant_ownership_transfer_canceled`

- `tenant`
- `owner`
- `pending_owner`

No ciphertext, nonce, or plaintext business content is emitted in event attributes.

## Helper Design Notes

The module separates concerns into deterministic helpers and focused keeper handlers:

- `types/validation.go`
- `types/canonical.go`
- `types/merkle.go`
- `keeper/msg_server_register_tenant.go`
- `keeper/msg_server_commit_integrity_set.go`
- `keeper/query_*.go`

The canonicalization and Merkle helpers are pure and directly unit-tested.

## Privacy Model

Kudora validates encrypted integrity commitments, not business semantics.

Kudora does not know:

- who the underlying expert is
- what the plaintext score payload contains
- which project a score belongs to
- how a client-side scoring algorithm works

Kudora only sees:

- tenant namespace
- dataset type string
- period string
- submitted Merkle root
- pseudonymous tags
- nonces
- ciphertext blobs

## Orbitrum Example Scope

Orbitrum appears only in:

- test-only mock builders under `testutil/integritymock/`
- the localnet smoke flow
- this documentation

It does not appear in production keeper, proto, store-key, or validation logic.

## Localnet Smoke Commands

Standalone mode:

```bash
make integrity-smoke-test
```

Against an already-running localnet:

```bash
KUDORA_USE_EXISTING_NODE=1 \
KUDORA_HOME=.localnet/validator0 \
KUDORA_RPC_URL=http://127.0.0.1:26657 \
KUDORA_EVM_RPC_URL=http://127.0.0.1:8545 \
KUDORA_RESULT_DIR=tmp/localnet \
make integrity-smoke-test
```

Full phase validation:

```bash
make phase-12-validate
make phase-12.1-lite-validate
```

For the ownership-transfer-only extension introduced after the initial Phase 12 MVP, see:

- `docs/modules/phase-12.1-lite-integrity-ownership-transfer.md`
