# Copilot Instructions for Kudora

## Project Overview

Kudora is a **Cosmos SDK blockchain with EVM compatibility**. It combines the Cosmos ecosystem (IBC, governance, staking) with Ethereum compatibility (JSON-RPC, smart contracts). The project is built with **Go 1.23+** and follows standard Cosmos SDK patterns.

## Architecture & Key Concepts

### Chain Configuration

- **Base Denom**: `kud` (18 decimals, matches Ethereum wei)
- **Display Denom**: `kudos`
- **Bech32 Prefix**: `kudo` (accounts: `kudo1...`, validators: `kudovaloper1...`)
- **Chain ID**: `kudora_12000-1` (mainnet) or `kudora-local-1` (localnet)
- **Binary**: `kudorad`

### Core Components

- **`app/app.go`**: Main application setup with all Cosmos SDK modules + EVM integration
- **`cmd/kudorad/`**: CLI binary with standard Cosmos SDK commands + Kudora-specific config
- **`app/config.go`**: Chain-specific configuration including `ChainsCoinInfo` mapping
- **EVM Integration**: Uses `github.com/cosmos/evm` for Ethereum compatibility

### Module Structure

Standard Cosmos SDK modules plus:

- **EVM module** for Ethereum compatibility
- **Token Factory** for custom token creation
- **IBC** for cross-chain communication
- **CosmWasm** for smart contracts
- Custom **precompiles** in `app/precompiles.go`

## Development Workflows

### Build & Install

```bash
make install          # Build and install kudorad binary
make build           # Build without installing
go install ./cmd/kudorad  # Direct go install
```

### Testing

```bash
make test            # Unit tests
make test-race       # Race condition testing
make test-cover      # Coverage testing
./scripts/test_node.sh  # Local devnet for integration testing
```

### Local Development

- **Quick devnet**: Use `./scripts/test_node.sh` with env vars:
  - `CHAIN_ID`, `HOME_DIR`, `BLOCK_TIME`, `CLEAN`, `RPC`, `REST` ports
- **Interchain testing**: See `interchaintest/` directory for cross-chain scenarios
- **EVM JSON-RPC**: Enable in `app.toml` for MetaMask/Web3 tools on port 8545

## Key Patterns & Conventions

### Configuration Management

- Chain configs are centralized in `app/app.go` constants
- Different chain IDs can have different coin info via `ChainsCoinInfo` map
- SDK config is sealed in `main.go` with Bech32 prefixes

### Import Patterns

```go
// Cosmos SDK core
sdk "github.com/cosmos/cosmos-sdk/types"
"github.com/cosmos/cosmos-sdk/x/auth"

// Cosmos EVM integration
"github.com/cosmos/evm/x/vm/types"
evmtypes "github.com/cosmos/evm/x/vm/types"

// IBC
"github.com/cosmos/ibc-go/v8/modules/apps/transfer"

// Project specific
"github.com/Kudora-Labs/kudora/app"
```

### Testing Conventions

- Use `interchaintest/setup.go` patterns for integration tests
- Test chain ID: `localchain_9000-1`
- E2E tests in `interchaintest/` use Docker containers
- Unit tests follow standard Go conventions with `_test.go` suffix

### Module Overrides

The project uses several **replace directives** in `go.mod` for:

- Custom Cosmos SDK fork from Strangelove
- Custom EVM module integration
- CosmWasm compatibility fixes
- Check `go.mod` for current overrides before module updates

## Critical Files for Understanding

- **`app/app.go`** (lines 1-300): Application setup and module registration
- **`app/config.go`**: Chain-specific configuration
- **`cmd/kudorad/main.go`**: Binary entry point and SDK config
- **`go.mod`**: Dependencies and critical replace directives
- **`interchaintest/setup.go`**: Testing infrastructure patterns

## Development Notes

- **Go version**: Requires Go 1.23+ (see `go.mod`)
- **Ledger support**: Controlled by `LEDGER_ENABLED` build flag
- **Cross-compilation**: Windows client builds supported (`make build-windows-client`)
- **Protocol generation**: Use `./scripts/protocgen.sh` for protobuf updates
- **EVM compatibility**: Enable JSON-RPC in config for Web3 tooling integration

## When Adding Features

1. **New modules**: Register in `app/app.go` module manager
2. **CLI commands**: Add to `cmd/kudorad/commands.go`
3. **Chain params**: Update `app/config.go` if chain-specific
4. **Integration tests**: Add to `interchaintest/` following existing patterns
5. **Precompiles**: Implement in `app/precompiles.go` for EVM integration
