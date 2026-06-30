# Candidate Cosmovisor Runtime

Phase 17 adds a candidate/devnet Cosmovisor runtime for Kudora.

The packaged runtime uses the official upstream Cosmovisor tool pinned to
`v1.6.0` for compatibility with the current Go `1.26.4` release baseline.

- `DAEMON_NAME=kudorad`
- `DAEMON_HOME=/home/nonroot/.kudora`
- `DAEMON_ALLOW_DOWNLOAD_BINARIES=false`
- `UNSAFE_SKIP_BACKUP=false`

This runtime is validated locally against the candidate genesis pipeline and is
not a final production mainnet deployment artifact.
