# Kudora Localnet

This directory contains the Docker Compose localnet for the current Kudora runtime baseline:

- Cosmos SDK chain
- Cosmos EVM JSON-RPC
- CosmWasm runtime

State is generated locally under `.localnet/` and is intentionally ignored by Git.

Primary commands from the repository root:

```bash
make localnet-init
make localnet-up
make localnet-smoke-test
make localnet-logs
make localnet-down
make localnet-reset
```

The default init path is Docker-first and does not require a host `build/kudorad` binary or a host Go toolchain.

Optional host-assisted debugging mode:

```bash
KUDORA_LOCALNET_INIT_MODE=host make localnet-init
```

See `docs/docker/phase-13-localnet.md` for the full operational guide.
See `docs/docker/phase-13.1-localnet-portability.md` for the portability and bind-mount ownership model.
See `docs/docker/phase-14-explorers.md` for the optional explorer stack that attaches to the running localnet.
See `docs/docker/phase-15-monitoring.md` for the optional Prometheus/Grafana monitoring stack that attaches to the same Docker network.
