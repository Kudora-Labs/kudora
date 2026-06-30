# Cosmovisor Candidate Runtime

Phase 17 adds a local-only Cosmovisor runtime for the Kudora candidate/devnet
release.

The runtime uses the official upstream `cosmossdk.io/tools/cosmovisor` binary,
currently pinned to `v1.6.0` for compatibility with the Go `1.26.4` release
tooling baseline.

## Commands

```bash
make cosmovisor-image-build
make cosmovisor-layout-verify
make cosmovisor-smoke-test
```

## Defaults

- `DAEMON_NAME=kudorad`
- `DAEMON_HOME=/home/nonroot/.kudora`
- `DAEMON_RESTART_AFTER_UPGRADE=true`
- `DAEMON_ALLOW_DOWNLOAD_BINARIES=false`
- `UNSAFE_SKIP_BACKUP=false`

The generated home stays under `tmp/phase-17-cosmovisor/` and is never a final
validator deployment artifact.
