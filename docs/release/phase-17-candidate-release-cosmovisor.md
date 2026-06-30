# Phase 17: Candidate Release, Docker Image, and Cosmovisor Runtime

Phase 17 adds a candidate/devnet release pipeline for the current Kudora
baseline without claiming final mainnet launch readiness.

## Release Classification

- release version: `v0.1.0-rc.1`
- release track: `candidate`
- release type: `devnet_candidate`
- mainnet launch-ready: `false`

This candidate release stays explicitly non-final because:

- the committed allocation addresses are temporary candidate public addresses;
- real validator gentx files are still required for final launch;
- Phase 17 does not publish a GitHub release, a Git tag, or a Docker registry image.

## Supported Candidate Artifacts

Current guaranteed binary package support:

- `linux/amd64`

Candidate release packaging produces:

- `release/manifest.json`
- `release/checksums.sha256`
- `out/release/kudora-v0.1.0-rc.1-linux-amd64.tar.gz`
- `out/release/kudora-v0.1.0-rc.1-source-context.zip`

The Linux package includes:

- `bin/kudorad`
- `lib/libwasmvm.x86_64.so`
- `genesis/genesis.json`
- `config/allocations.json`
- `manifest.json`
- `checksums.sha256`
- `README.md`

## Docker Image

Phase 17 adds local-only candidate image validation for:

- `kudora/kudorad:v0.1.0-rc.1`
- `kudora/kudorad:latest-rc`

The image keeps:

- non-root runtime
- the current Kudora ports
- wasmvm runtime shared libraries
- OCI labels for release version, git commit, release track, and `mainnet_launch_ready=false`

No Docker registry push is performed in this phase.

## Cosmovisor Runtime

The candidate Cosmovisor image is built locally and validated against a
temporary home under `tmp/phase-17-cosmovisor/`.

For the current Go `1.26.4` baseline, Kudora pins the official upstream
Cosmovisor tool to `v1.6.0`. The newer `v1.7.x` line did not pass local build
validation in this environment, so Phase 17 keeps the latest locally validated
official upstream version instead of introducing a fork or a patch.

Default runtime policy:

- `DAEMON_NAME=kudorad`
- `DAEMON_HOME=/home/nonroot/.kudora`
- `DAEMON_RESTART_AFTER_UPGRADE=true`
- `DAEMON_ALLOW_DOWNLOAD_BINARIES=false`
- `UNSAFE_SKIP_BACKUP=false`

The home layout is validated with:

- `$DAEMON_HOME/cosmovisor/genesis/bin/kudorad`
- `$DAEMON_HOME/cosmovisor/current -> genesis`

The smoke validation starts a temporary candidate/devnet node through
`cosmovisor run start`, checks CometBFT RPC, and confirms the EVM RPC still
returns `eth_chainId = 0x1d4c1`.

## Validation Commands

```bash
make release-build-binaries
make release-package
make release-verify
make release-docker-build
make release-docker-verify
make cosmovisor-image-build
make cosmovisor-layout-verify
make cosmovisor-smoke-test
make phase-17-validate
```

## Operator Caveat

This is not a production launch artifact. Final production allocation wallets,
real validator gentx files, and a launch plan are still required before Kudora
can claim a mainnet-ready release.
