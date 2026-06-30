# Phase 13.1 Docker Localnet Portability

Phase 13.1 hardens the Phase 13 localnet so the default initialization path is Docker-first and portable across clean contributor machines.

## Default Init Mode

`make localnet-init` now defaults to Docker mode.

In Docker mode:

- the local Kudora image `kudora/kudorad:localnet` performs chain initialization
- the same image generates the local EVM smoke account helper output
- no host `build/kudorad` binary is required
- no host Go toolchain is required

The generated node home remains local-only under `.localnet/validator0`.

## Optional Host-Assisted Mode

An explicit host-assisted mode is still available for debugging:

```bash
KUDORA_LOCALNET_INIT_MODE=host make localnet-init
```

Host mode requires:

- `build/kudorad` or `make build`
- a local Go toolchain, because the EVM smoke helper is built on the host

Host mode is not the default and is not the portability baseline.

## Bind Mount Ownership Model

The localnet portability baseline uses a fixed non-root runtime user:

```yaml
user: "${LOCALNET_RUNTIME_UID:-65532}:${LOCALNET_RUNTIME_GID:-65532}"
```

The Docker-first init path creates the bind-mounted state with the same non-root ownership model, so the running validator does not need root or world-writable permissions.

`LOCAL_UID` and `LOCAL_GID` are still recorded for audit visibility, but the portable runtime strategy is the fixed image-compatible non-root user pair.

The stable localnet network name is:

```text
kudora-localnet
```

This also prepares the repo for later explorer attachment without hardcoded container IPs.

## Supported Platforms

The intended portable baseline is:

- Linux with Docker Engine and Compose
- macOS with Docker Desktop
- macOS with Colima plus Docker CLI/Compose
- CI-style Linux runners with Docker access

## Required Host Tools

Required for localnet init and lifecycle:

- Docker daemon access
- `docker compose` or `docker-compose`
- `jq`
- `perl`

Required for localnet smoke reuse against the running node:

- `curl`
- `jq`
- the repository Go build path, because the existing EVM/CosmWasm smoke scripts still use host-side helpers and CLI flows

## Current Local-Only Scope

The localnet remains intentionally local-only and not production-ready:

- one validator service
- generated local keys only
- local-only state under `.localnet/`
- local-only smoke artifacts under `tmp/localnet/`
- no relayer
- no tokenfactory
- no packet-forward
- no rate-limit
- no ICA
- no 08-wasm
- no explorers in Phase 13.1 itself; Phase 14 adds them as a separate local-only stack

## Validation Notes

Phase 13 and Phase 13.1 validation now assert that:

- default init mode is Docker mode
- default init succeeds without a host `build/kudorad`
- default init succeeds without host Go in the execution `PATH`
- the localnet container does not run as root
- block height strictly increases during smoke validation
- smoke result artifacts are generated during the current run only
