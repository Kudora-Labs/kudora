package app

import (
	"testing"

	"github.com/ethereum/go-ethereum/common"
	"github.com/stretchr/testify/require"
)

// TestKudoraPrecompiles tests the initialization and availability of all precompiles
func TestKudoraPrecompiles(t *testing.T) {
	app := Setup(t)

	// Get precompiles map
	precompiles := NewAvailableStaticPrecompiles(
		*app.StakingKeeper,
		app.DistrKeeper,
		app.BankKeeper,
		app.Erc20Keeper,
		app.AuthzKeeper,
		app.TransferKeeper,
		app.IBCKeeper.ChannelKeeper,
		app.EVMKeeper,
		app.GovKeeper,
		app.SlashingKeeper,
		app.EvidenceKeeper,
	)

	// Verify we have the expected number of precompiles
	// Should include: standard EVM precompiles + custom ones
	require.GreaterOrEqual(t, len(precompiles), 9, "should have at least 9 precompiles")

	// Test precompile addresses are valid and non-zero
	addressCount := 0
	for addr, precompile := range precompiles {
		require.NotEqual(t, common.Address{}, addr, "precompile address should not be zero")
		require.NotNil(t, precompile, "precompile implementation should not be nil")
		addressCount++
	}

	require.Equal(t, len(precompiles), addressCount, "all precompiles should have valid addresses")
}

// TestKudoraPrecompileInitialization tests that precompiles initialize without errors
func TestKudoraPrecompileInitialization(t *testing.T) {
	app := Setup(t)

	// Test that initialization doesn't panic
	require.NotPanics(t, func() {
		NewAvailableStaticPrecompiles(
			*app.StakingKeeper,
			app.DistrKeeper,
			app.BankKeeper,
			app.Erc20Keeper,
			app.AuthzKeeper,
			app.TransferKeeper,
			app.IBCKeeper.ChannelKeeper,
			app.EVMKeeper,
			app.GovKeeper,
			app.SlashingKeeper,
			app.EvidenceKeeper,
		)
	}, "precompile initialization should not panic")
}

// TestKudoraPrecompileGasCosts tests gas cost constants
func TestKudoraPrecompileGasCosts(t *testing.T) {
	// Test bech32 precompile base gas
	require.Equal(t, 6000, bech32PrecompileBaseGas, "bech32 precompile gas cost should be 6000")
	require.Greater(t, bech32PrecompileBaseGas, 0, "gas cost should be positive")
}

// TestKudoraPrecompileAddresses tests that precompile addresses are deterministic
func TestKudoraPrecompileAddresses(t *testing.T) {
	app := Setup(t)

	// Initialize precompiles twice and ensure addresses are consistent
	precompiles1 := NewAvailableStaticPrecompiles(
		*app.StakingKeeper,
		app.DistrKeeper,
		app.BankKeeper,
		app.Erc20Keeper,
		app.AuthzKeeper,
		app.TransferKeeper,
		app.IBCKeeper.ChannelKeeper,
		app.EVMKeeper,
		app.GovKeeper,
		app.SlashingKeeper,
		app.EvidenceKeeper,
	)

	precompiles2 := NewAvailableStaticPrecompiles(
		*app.StakingKeeper,
		app.DistrKeeper,
		app.BankKeeper,
		app.Erc20Keeper,
		app.AuthzKeeper,
		app.TransferKeeper,
		app.IBCKeeper.ChannelKeeper,
		app.EVMKeeper,
		app.GovKeeper,
		app.SlashingKeeper,
		app.EvidenceKeeper,
	)

	// Addresses should be the same
	require.Equal(t, len(precompiles1), len(precompiles2), "precompile count should be consistent")

	for addr := range precompiles1 {
		_, exists := precompiles2[addr]
		require.True(t, exists, "precompile address should be deterministic: %s", addr.Hex())
	}
}

// TestKudoraPrecompileNonConflicting tests that precompile addresses don't conflict
func TestKudoraPrecompileNonConflicting(t *testing.T) {
	app := Setup(t)

	precompiles := NewAvailableStaticPrecompiles(
		*app.StakingKeeper,
		app.DistrKeeper,
		app.BankKeeper,
		app.Erc20Keeper,
		app.AuthzKeeper,
		app.TransferKeeper,
		app.IBCKeeper.ChannelKeeper,
		app.EVMKeeper,
		app.GovKeeper,
		app.SlashingKeeper,
		app.EvidenceKeeper,
	)

	// Collect all addresses
	addresses := make([]common.Address, 0, len(precompiles))
	for addr := range precompiles {
		addresses = append(addresses, addr)
	}

	// Check for duplicates
	for i, addr1 := range addresses {
		for j, addr2 := range addresses {
			if i != j {
				require.NotEqual(t, addr1, addr2, "precompile addresses should not conflict: %s vs %s", addr1.Hex(), addr2.Hex())
			}
		}
	}
}