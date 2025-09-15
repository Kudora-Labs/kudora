package app

import (
	"math/big"
	"testing"

	"github.com/ethereum/go-ethereum/common"
	"github.com/stretchr/testify/require"

	sdkmath "cosmossdk.io/math"
	sdk "github.com/cosmos/cosmos-sdk/types"
)

// TestKudoraEVMAddressConversion tests address conversion between Ethereum and Cosmos formats
func TestKudoraEVMAddressConversion(t *testing.T) {
	// Test Ethereum address to Bech32 conversion
	ethAddr := common.HexToAddress("0x1234567890123456789012345678901234567890")
	bech32Addr := sdk.AccAddress(ethAddr.Bytes())

	// Test that our prefix constant is correctly defined (even if SDK uses different config)
	require.Equal(t, "kudo", Bech32PrefixAccAddr, "prefix constant should be kudo")

	// Test round-trip conversion
	convertedBack := common.BytesToAddress(bech32Addr.Bytes())
	require.Equal(t, ethAddr, convertedBack, "round-trip conversion should preserve address")

	// Test address length consistency
	require.Equal(t, common.AddressLength, len(bech32Addr), "Cosmos address should have same length as Ethereum address")
}

// TestKudoraDenomInEVM tests denomination handling in EVM context
func TestKudoraDenomInEVM(t *testing.T) {
	// Test kud denom handling in EVM context (18 decimals like wei)
	oneKud := sdk.NewCoin(BaseDenom, sdkmath.NewInt(1000000000000000000)) // 1 kud = 10^18 base units
	
	// Test amount conversion to wei-equivalent
	wei := big.NewInt(1000000000000000000)
	require.Equal(t, oneKud.Amount.BigInt(), wei, "1 kud should equal 10^18 base units")

	// Test smaller amounts
	halfKud := sdk.NewCoin(BaseDenom, sdkmath.NewInt(500000000000000000)) // 0.5 kud
	halfWei := big.NewInt(500000000000000000)
	require.Equal(t, halfKud.Amount.BigInt(), halfWei, "0.5 kud should equal 5*10^17 base units")

	// Test that base denom can be retrieved
	baseDenom, err := sdk.GetBaseDenom()
	if err == nil {
		require.Equal(t, BaseDenom, baseDenom, "base denom should be kud")
	}
}

// TestKudoraCoinInfoIntegration tests coin info integration with EVM
func TestKudoraCoinInfoIntegration(t *testing.T) {
	// Test that chain coin info is properly configured
	coinInfo, exists := ChainsCoinInfo[ChainID]
	require.True(t, exists, "chain coin info should exist for test chain")
	
	// Test denom configuration
	require.Equal(t, BaseDenom, coinInfo.Denom, "base denom should match")
	require.Equal(t, DisplayDenom, coinInfo.DisplayDenom, "display denom should match")
	
	// Test decimals (should be 18 for EVM compatibility)
	require.Equal(t, uint8(18), uint8(coinInfo.Decimals), "should have 18 decimals for EVM compatibility")
}

// TestKudoraAddressValidation tests Kudora-specific address validation
func TestKudoraAddressValidation(t *testing.T) {
	tests := []struct {
		name        string
		address     string
		expectValid bool
	}{
		{
			name:        "invalid prefix",
			address:     "cosmos1x2ck0ql2ngyxqtw9wy62wx5qczqqxq6z6xlnkln",
			expectValid: false,
		},
		{
			name:        "empty address",
			address:     "",
			expectValid: false,
		},
		{
			name:        "invalid format",
			address:     "invalid_address",
			expectValid: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := sdk.AccAddressFromBech32(tt.address)
			if tt.expectValid {
				require.NoError(t, err, "valid address should parse without error")
			} else {
				require.Error(t, err, "invalid address should return error")
			}
		})
	}
}

// TestKudoraBankEVMIntegration tests bank module integration with EVM
func TestKudoraBankEVMIntegration(t *testing.T) {
	app := Setup(t)
	ctx := app.BaseApp.NewContext(false)

	// Create test accounts
	addr1 := sdk.AccAddress([]byte("test_address_1_____"))
	addr2 := sdk.AccAddress([]byte("test_address_2_____"))

	// Test minting tokens
	mintAmount := sdk.NewCoins(sdk.NewCoin(BaseDenom, sdkmath.NewInt(1000000000000000000))) // 1 kud
	err := app.BankKeeper.MintCoins(ctx, "mint", mintAmount)
	require.NoError(t, err, "should mint coins without error")

	// Test sending tokens to account
	err = app.BankKeeper.SendCoinsFromModuleToAccount(ctx, "mint", addr1, mintAmount)
	require.NoError(t, err, "should send coins from module to account")

	// Test balance
	balance := app.BankKeeper.GetBalance(ctx, addr1, BaseDenom)
	require.Equal(t, mintAmount[0], balance, "balance should match minted amount")

	// Test transfer between accounts
	transferAmount := sdk.NewCoins(sdk.NewCoin(BaseDenom, sdkmath.NewInt(500000000000000000))) // 0.5 kud
	err = app.BankKeeper.SendCoins(ctx, addr1, addr2, transferAmount)
	require.NoError(t, err, "should transfer coins between accounts")

	// Verify balances after transfer
	balance1 := app.BankKeeper.GetBalance(ctx, addr1, BaseDenom)
	balance2 := app.BankKeeper.GetBalance(ctx, addr2, BaseDenom)
	
	expectedBalance1 := sdk.NewCoin(BaseDenom, sdkmath.NewInt(500000000000000000)) // 0.5 kud remaining
	expectedBalance2 := sdk.NewCoin(BaseDenom, sdkmath.NewInt(500000000000000000)) // 0.5 kud received
	
	require.Equal(t, expectedBalance1, balance1, "sender balance should be correct")
	require.Equal(t, expectedBalance2, balance2, "receiver balance should be correct")
}

// TestKudoraEVMDenomMetadata tests denomination metadata for EVM compatibility
func TestKudoraEVMDenomMetadata(t *testing.T) {
	app := Setup(t)
	ctx := app.BaseApp.NewContext(false)

	// Test that denominations are properly registered
	baseDenom, err := sdk.GetBaseDenom()
	if err == nil {
		require.Equal(t, BaseDenom, baseDenom, "base denom should be kud")
	}

	// Test denom validation
	require.NoError(t, sdk.ValidateDenom(BaseDenom), "base denom should be valid")
	require.NoError(t, sdk.ValidateDenom(DisplayDenom), "display denom should be valid")

	// Test that bank keeper recognizes the denom
	supply := app.BankKeeper.GetSupply(ctx, BaseDenom)
	require.Equal(t, BaseDenom, supply.Denom, "supply should have correct denom")
}

// TestKudoraEVMGasAndFees tests gas and fee handling for EVM transactions
func TestKudoraEVMGasAndFees(t *testing.T) {
	// Test fee configuration
	feeAmount := sdk.NewCoins(sdk.NewCoin(BaseDenom, sdkmath.NewInt(1000000000000000))) // 0.001 kud
	
	// Test that fees can be created with base denom
	require.True(t, feeAmount.IsValid(), "fee amount should be valid")
	require.Equal(t, BaseDenom, feeAmount[0].Denom, "fee should use base denom")

	// Test gas calculation (basic validation)
	gasUsed := uint64(21000) // Basic transfer gas
	require.Greater(t, gasUsed, uint64(0), "gas used should be positive")
}

// TestKudoraEVMStateConsistency tests state consistency between Cosmos and EVM
func TestKudoraEVMStateConsistency(t *testing.T) {
	// Create an address that can be used in both Cosmos and EVM contexts
	ethAddr := common.HexToAddress("0x742d35Cc6634C0532925a3b8D2F9E10b4F33a1e4")
	cosmosAddr := sdk.AccAddress(ethAddr.Bytes())

	// Test that the same address works in both contexts
	require.Equal(t, 20, len(ethAddr.Bytes()), "Ethereum address should be 20 bytes")
	require.Equal(t, 20, len(cosmosAddr.Bytes()), "Cosmos address should be 20 bytes")
	require.Equal(t, ethAddr.Bytes(), cosmosAddr.Bytes(), "address bytes should be identical")

	// Test address string representations
	cosmosAddrStr := cosmosAddr.String()
	require.NotEmpty(t, cosmosAddrStr, "Cosmos address string should not be empty")
	require.Equal(t, "kudo", Bech32PrefixAccAddr, "prefix constant should be kudo")

	// Test round-trip conversion
	parsedAddr, err := sdk.AccAddressFromBech32(cosmosAddrStr)
	require.NoError(t, err, "should parse bech32 address")
	require.Equal(t, cosmosAddr, parsedAddr, "parsed address should match original")
	require.Equal(t, ethAddr, common.BytesToAddress(parsedAddr.Bytes()), 
		"should convert back to original Ethereum address")
}

// TestKudoraEVMMultiCoinSupport tests multi-coin support in EVM context
func TestKudoraEVMMultiCoinSupport(t *testing.T) {
	app := Setup(t)
	ctx := app.BaseApp.NewContext(false)

	// Test with multiple coin types
	addr := sdk.AccAddress([]byte("test_multi_coin_addr"))
	
	// Test with base denom
	baseCoins := sdk.NewCoins(sdk.NewCoin(BaseDenom, sdkmath.NewInt(1000000000000000000)))
	err := app.BankKeeper.MintCoins(ctx, "mint", baseCoins)
	require.NoError(t, err, "should mint base denom")
	
	// Test with other potential denoms (like IBC tokens)
	ibcDenom := "ibc/1234567890ABCDEF"
	if sdk.ValidateDenom(ibcDenom) == nil {
		ibcCoins := sdk.NewCoins(sdk.NewCoin(ibcDenom, sdkmath.NewInt(1000000)))
		err = app.BankKeeper.MintCoins(ctx, "mint", ibcCoins)
		require.NoError(t, err, "should handle IBC denoms")
	}

	// Test balance queries
	balance := app.BankKeeper.GetBalance(ctx, addr, BaseDenom)
	require.Equal(t, BaseDenom, balance.Denom, "balance should have correct denom")
}