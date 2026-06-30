# Phase 2 Official EVM Path Decision

Status note after Phase 3:

- the path chosen here was implemented in Phase 3;
- the decision record remains relevant as the rationale for using upstream `evmd`;
- Kudora now has minimal EVM runtime support in-tree.

## Scope

Phase 2 evaluates the most official and maintainable Cosmos EVM path for Kudora without wiring EVM into the chain yet.

Active baseline note:

- Kudora's official Cosmos chain-id is `kudora_12000-1`.
- Earlier planning references to `kudora_12000-2` are superseded.

Kudora constraints for this decision:

- stay close to official Ignite and Cosmos EVM tooling;
- avoid custom Cosmos core maintenance;
- do not add unofficial forks;
- do not derive the final EVM chain ID implicitly;
- do not enable EVM runtime support in this phase.

## Commands Inspected

The following local commands were inspected with the currently installed Ignite release:

- `ignite version`
- `ignite scaffold --help`
- `ignite scaffold chain --help`
- `ignite chain --help`
- `ignite app --help || true`
- `ignite app list || true`
- `ignite appregistry --help || true`
- `ignite appregistry list || true`

EVM-specific searches were also run against the scaffold commands.

## Ignite Discovery Results

### 1. Core scaffold commands

- `ignite scaffold --help` exposes no first-class `evm`, `ethereum`, `ethermint`, or `cosmos-evm` scaffold target.
- `ignite scaffold chain --help` exposes no EVM-specific flag or mode.
- `ignite chain --help` exposes build, serve, init, faucet, simulate, debug, lint, and modules commands, but no built-in EVM integration command.

Conclusion:

- Ignite CLI does not provide EVM as a first-class core scaffold path in the main `scaffold chain` workflow.

### 2. Official Ignite app ecosystem

The official `ignite/apps` repository was cloned to `tmp/ignite-apps` and inspected directly because local app registry commands failed in this environment.

Observed official sources:

- `_registry/ignite.apps.evm.json`
- `app.ignite.yml`
- `evm/README.md`
- `evm/CHANGELOG.md`
- `evm/integration/app_test.go`

What this proves:

- an official Ignite EVM app does exist in the official `ignite/apps` repository;
- it is not a random marketplace app;
- it includes documentation, a changelog, and an integration test;
- `go test ./...` passed locally in `tmp/ignite-apps/evm`, including the integration test.

## Why The Official Ignite EVM App Is Not The Kudora Integration Path

The official Ignite EVM app is real and maintained, but it is not the right implementation path for Kudora under the current repository rules.

### A. App registry discovery is not reliable in the current validated environment

`ignite app list` and `ignite appregistry list` failed locally while building the official `appregistry` app. The failure came from `github.com/bytedance/sonic` during the plugin build step.

This matters because:

- Phase 2 needs a reproducible enterprise baseline;
- a fragile app discovery path is not a good foundation for Kudora's long-term EVM rollout.

### B. The Ignite EVM app is behind upstream Cosmos EVM

The official Ignite EVM app currently targets:

- `github.com/ignite/cli/v29 v29.9.2`
- `github.com/cosmos/evm v0.6.0`

The latest stable upstream Cosmos EVM release inspected in Phase 2 is:

- repository tag `v0.7.0`
- commit `f4ab9a3e3fbe353468327d5cacda94b33b41ed11`

That means the Ignite app is behind the upstream reference implementation that Kudora would ultimately need to follow.

### C. The Ignite EVM app injects a `go-ethereum` fork replacement

The official Ignite EVM app template explicitly adds:

- `replace github.com/ethereum/go-ethereum => github.com/cosmos/go-ethereum v1.16.2-cosmos-1`

This is not acceptable for Kudora under the current repository no-forks policy.

### D. The Ignite EVM app derives the EVM chain ID from the Cosmos chain ID

The official Ignite EVM app template includes a helper that hashes the Cosmos chain ID with FNV and converts that hash into the EVM chain ID.

That is not acceptable for Kudora because Phase 2 requires:

- a fixed, explicit EVM chain ID;
- no implicit hash-derived chain ID strategy.

## Decision

### Chosen official path for the next implementation phase

Use the upstream `cosmos/evm` `evmd` reference implementation as the design and integration reference.

### Explicit non-decision

Do not use the Ignite EVM app as Kudora's implementation path.

Reason summary:

- not first-class in `ignite scaffold chain`;
- local app registry flow is currently fragile in this validated environment;
- app version lags upstream Cosmos EVM;
- app template injects a `go-ethereum` fork replacement;
- app template derives EVM chain ID from Cosmos chain ID hashing.

## Phase 2.1 Dependency Policy Outcome

Even the upstream `cosmos/evm v0.7.0` reference still replaces:

- `github.com/ethereum/go-ethereum`
- with `github.com/cosmos/go-ethereum v1.17.2-cosmos-0`

Phase 2.1 approves a narrow controlled exception for that exact upstream replacement only when it is used together with:

- `github.com/cosmos/evm v0.7.0`

The detailed policy is documented in:

- `docs/evm/phase-2.1-evm-dependency-policy.md`

Therefore the implementation status after Phase 2.1 was:

- official design source: upstream `evmd`;
- dependency policy status: conditionally unblocked for Phase 3 only under the approved narrow exception;
- runtime status at that point: still inactive in Kudora.
- explicit runtime candidate values for the next phase:
  - Cosmos chain-id: `kudora_12000-1`
  - EVM chain ID candidate: `120001`
  - expected `eth_chainId`: `0x1d4c1`

Additional Phase 2 validation note:

- `go test ./... -run '^$'` passed locally in `tmp/cosmos-evm/evmd`, so the upstream reference compiled successfully in the current workstation environment even though its dependency policy is still not acceptable for Kudora.

## Phase 2 Outcome

Phase 2 itself did not activate EVM in Kudora. That activation happens later in Phase 3.

Phase 2 delivers:

- a documented official path decision;
- a compatibility matrix;
- an integration design for the next phase;
- validation rules that prevent accidental partial EVM wiring.

Phase 2.1 adds:

- an auditable dependency policy exception for the official Cosmos-maintained `go-ethereum` fork required by upstream `cosmos/evm v0.7.0`;
- a narrowed `verify-no-forks.sh` rule set that enforces that exception precisely;
- explicit confirmation that EVM runtime was still inactive before Phase 3.
