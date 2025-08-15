# Kudora

A Cosmos SDK-based blockchain project by Kudora Labs, featuring IBC connectivity, EVM compatibility, and comprehensive testing infrastructure.

## Overview

Kudora is a next-generation blockchain application built on the proven Cosmos SDK framework with EVM compatibility, enabling seamless interoperability and smart contract development.

## Features

- **Cosmos SDK Integration**: Built on the proven Cosmos SDK framework
- **IBC Connectivity**: Inter-blockchain communication capabilities for cross-chain interactions
- **EVM Compatible**: Full Solidity smart contract support with Ethereum tooling compatibility
- **Local Development Environment**: Complete testnet setup with IBC connectivity
- **Comprehensive Testing**: Simulation testing and interchain testing infrastructure
- **Custom Modules**: Specialized modules for enhanced blockchain functionality
- **Upgrade Management**: Built-in upgrade handlers for seamless network upgrades

## Quick Start

### Prerequisites

- Go 1.23+
- Docker & Docker Compose
- Make
- Node.js (for EVM tooling)

### Local Development

#### Option 1: Full IBC Testnet (Recommended)

```bash
# Full setup: docker image, binary, keys, and IBC testnet start
make testnet

# IBC testnet with CosmosHub connectivity
spawn local-ic start testnet
```

#### Option 2: Standalone Node

```bash
# Simple local node with shell script
make sh-testnet

# Manual script execution with custom parameters
CHAIN_ID="localchain_9000-1" HOME_DIR="~/.kudora" BLOCK_TIME="1000ms" CLEAN=true sh scripts/test_node.sh
```

#### Option 3: Custom Configuration

```bash
# Build and install binary
make install

# Initialize chain
kudorad init localvalidator --chain-id localchain_9000-1 --default-denom kud

# Start with custom ports
CHAIN_ID="localchain_9000-2" RPC=36657 REST=2317 P2P=36656 GRPC=8090 sh scripts/test_node.sh
```

### Building

```bash
# Build the binary
make build

# Install binary to GOPATH
make install

# Install dependencies
go mod download

# Build Docker image
make docker-build
```

## Network Configuration

### Default Settings

- **Chain ID**: `localchain_9000-1`
- **Base Denomination**: `kud`
- **Display Denomination**: `kudos`
- **RPC Port**: `26657`
- **REST API Port**: `1317`
- **GRPC Port**: `9090`
- **P2P Port**: `26656`
- **Home Directory**: `~/.kudora`

### Test Accounts

The local testnet comes with pre-configured test accounts with sufficient balances for development and testing.

## Project Structure

```
├── app/                    # Application logic and configuration
│   ├── ante/              # Ante handlers for transaction processing
│   ├── decorators/        # Custom transaction decorators
│   ├── params/            # Parameter management and validation
│   └── upgrades/          # Network upgrade handlers
├── chains/                # Local-interchain configurations
├── cmd/                   # Command-line interfaces
│   └── kudorad/          # Main daemon binary
├── contrib/               # Development tools and utilities
├── interchaintest/        # Interchain testing framework
├── proto/                 # Protocol buffer definitions
├── scripts/               # Build and deployment scripts
│   ├── test_node.sh      # Local testnet setup script
│   └── protocgen.sh      # Protocol buffer generation
├── x/                     # Custom Cosmos SDK modules
└── docs/                  # Documentation
```

## Configuration Files

- `chains.yaml` - Local-interchain chain configuration
- `chain_metadata.json` - Chain metadata and parameters
- `chain_registry.json` - Chain registry information for IBC
- `chain_registry_assets.json` - Asset registry for tokens and denominations
- `Dockerfile` - Container build configuration
- `docker-compose.yml` - Multi-service development environment

## Testing

The project includes comprehensive testing infrastructure:

### Test Types

- **Unit Tests**: Standard Go unit tests for individual components
- **Integration Tests**: Cross-module functionality testing
- **Simulation Tests**: Cosmos SDK simulation testing framework
- **Interchain Tests**: Multi-chain interaction and IBC testing
- **E2E Tests**: End-to-end application testing

### Running Tests

```bash
# Run all tests
make test

# Run unit tests only
make test-unit

# Run simulation tests
make test-sim

# Run integration tests
make test-integration

# Run interchain tests
make test-interchain

# Test with race detection
make test-race

# Generate test coverage
make test-cover
```

## Development Workflow

### 1. Setup Development Environment

```bash
# Clone and setup
git clone <repository-url>
cd kudora
make install

# Start local testnet
make sh-testnet
```

### 2. Development Commands

```bash
# Generate protocol buffers
make proto-gen

# Format code
make format

# Lint code
make lint

# Clean build artifacts
make clean
```

### 3. EVM Development

```bash
# Deploy smart contracts (if EVM module is configured)
# Connect to JSON-RPC endpoint at http://localhost:8545 (if available)
```

## Local Testnet

### IBC Testnet Features

- **Multi-Chain Setup**: Kudora chain + CosmosHub testnet
- **IBC Relayer**: Automatic packet relaying between chains
- **Docker Environment**: Isolated and reproducible setup
- **Pre-configured Keys**: Ready-to-use test accounts
- **Token Transfers**: Cross-chain asset transfers via IBC

### Testnet Management

```bash
# Start full testnet
make testnet

# Stop testnet
spawn local-ic stop

# Clean testnet data
spawn local-ic clean

# View logs
docker logs kudora-chain
```

For detailed testnet configuration, see [chains/README.md](chains/README.md).

## API Endpoints

When running locally, the following endpoints are available:

- **RPC**: `http://localhost:26657`
- **REST API**: `http://localhost:1317`
- **GRPC**: `localhost:9090`
- **EVM JSON-RPC**: `http://localhost:8545` (if EVM module enabled)

## Modules

Kudora includes both standard Cosmos SDK modules and custom modules:

### Standard Modules

- `auth`, `bank`, `staking`, `distribution`, `gov`, `slashing`
- `ibc`, `transfer`, `capability`
- `params`, `upgrade`, `evidence`

### Custom Modules

Located in the `x/` directory - these provide Kudora-specific functionality.

## Upgrades

Network upgrades are managed through the upgrade module:

```bash
# Propose upgrade (example)
kudorad tx gov submit-proposal software-upgrade v2.0.0 \
  --title "Upgrade to v2.0.0" \
  --description "Major network upgrade" \
  --upgrade-height 1000 \
  --from validator
```

## Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for detailed information on:

- How to submit issues and pull requests
- Branch naming conventions
- Code review requirements
- Development guidelines

### Quick Contributing Steps

1. Fork the repository
2. Create a feature branch following our naming convention
3. Make your changes and add tests
4. Submit a pull request

For detailed guidelines, please read [CONTRIBUTING.md](CONTRIBUTING.md).

## Documentation

- [Cosmos SDK Documentation](https://docs.cosmos.network/)
- [IBC Protocol Documentation](https://ibc.cosmos.network/)
- [Local-Interchain Documentation](https://github.com/strangelove-ventures/interchaintest/tree/main/local-interchain)
- [Ethermint Documentation](https://docs.ethermint.zone/) (for EVM compatibility)

## Troubleshooting

### Common Issues

**Port conflicts**: If ports are already in use, modify the port configuration in the start script or use custom ports:

```bash
RPC=36657 REST=2317 P2P=36656 GRPC=8090 sh scripts/test_node.sh
```

**Permission errors**: Ensure Docker daemon is running and your user has Docker permissions.

**Build failures**: Ensure you have Go 1.23+ installed and all dependencies are available.

## Security

- This is development software - do not use in production without proper security review
- Test accounts contain pre-funded balances for development only
- Private keys in the repository are for testing purposes only

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

Copyright (c) 2025 Kudora Labs

## Acknowledgments

Thanks to the entire Cosmos SDK team and the contributors who put their efforts into making simulation testing easier to implement. 🤗

Special thanks to:

- Cosmos SDK team for the robust blockchain framework
- Strangelove Ventures for the interchain testing tools
- Ethermint team for EVM compatibility

## Support

For questions and support:

- Create an issue in this repository
- Contact the Kudora Labs team
- Join our community channels

---

**Happy Building! 🚀**
