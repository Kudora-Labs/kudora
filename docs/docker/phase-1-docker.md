# Docker Baseline

This document started in Phase 1 as the minimal Docker baseline and remains the reference for the container packaging layer after the Phase 3 EVM runtime work and the Phase 5 minimal CosmWasm runtime integration.

## Purpose

The Docker image provides a reproducible build of `kudorad` and a minimal non-root runtime image that can be reused in later phases.

## Current Image Scope

The current image includes:

- multi-stage build from source
- official Go builder image
- minimal non-root runtime image
- `kudorad` binary only
- official EVM and CosmWasm runtime code compiled into the same binary
- Cosmos node ports:
  - `26656`
  - `26657`
  - `1317`
  - `9090`
- EVM runtime ports after Phase 3:
  - `8545`
  - `8546`
- no dedicated CosmWasm network ports, because Wasm execution shares the main chain process and standard Cosmos APIs

## Intentionally Excluded

The image still does not include:

- local node homes
- generated validator or node keys
- `.env` files
- production bootstrapping
- mainnet genesis
- monitoring stack
- production explorer infrastructure; Phase 14 adds a separate local-only explorer layer on top of this image
- release publishing logic

## Makefile Commands

```bash
make docker-build
make docker-version
make docker-smoke-test
make evm-smoke-test
```

The local validation image tag is now:

```text
kudora/kudorad:localnet
```

## Security Notes

- The image runs as a non-root user.
- The builder keeps `CGO_ENABLED=1` because Kudora now depends on both upstream `github.com/cosmos/evm v0.7.0` and upstream `github.com/CosmWasm/wasmvm/v3`.
- The final image now copies the official prebuilt `libwasmvm` shared libraries from the Go module cache so the non-root runtime can execute CosmWasm contracts without bundling any local node state.
- The Docker build context excludes Git history, local homes, testnets, logs, release artifacts, zip archives, `.env` files, and common key file patterns.
- The image does not embed validator state, node homes, secrets, or credentials.
- The default container command remains `kudorad version --long`, so the basic image smoke path does not create node state.

## Operational Notes

Phase 5 adds minimal CosmWasm runtime support to the same binary, but this is still not a claim that Docker alone is sufficient for production validator operations, public JSON-RPC exposure, or CosmWasm governance operations.

Production-oriented work remains for later phases:

- rehearsal environments
- operational hardening of JSON-RPC exposure
- monitoring
- advanced release packaging

Phase 13 now adds a separate Docker Compose localnet layer documented in `docs/docker/phase-13-localnet.md`. The base image remains the same reusable non-root image.
