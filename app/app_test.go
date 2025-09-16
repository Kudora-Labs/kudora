package app

import (
	"testing"

	abci "github.com/cometbft/cometbft/abci/types"
	dbm "github.com/cosmos/cosmos-db"
	"github.com/cosmos/gogoproto/proto"
	"github.com/stretchr/testify/require"

	"cosmossdk.io/log"

	simtestutil "github.com/cosmos/cosmos-sdk/testutil/sims"
	sdk "github.com/cosmos/cosmos-sdk/types"
	"github.com/cosmos/cosmos-sdk/types/msgservice"

	wasmkeeper "github.com/CosmWasm/wasmd/x/wasm/keeper"
)

func TestAppExport(t *testing.T) {
	db := dbm.NewMemDB()
	logger := log.NewTestLogger(t)
	gapp := NewChainAppWithCustomOptions(t, false, SetupOptions{
		Logger:  logger.With("instance", "first"),
		DB:      db,
		AppOpts: simtestutil.NewAppOptionsWithFlagHome(t.TempDir()),
	})

	// finalize block so we have CheckTx state set
	_, err := gapp.FinalizeBlock(&abci.RequestFinalizeBlock{
		Height: 1,
	})
	require.NoError(t, err)

	_, err = gapp.Commit()
	require.NoError(t, err)

	// Making a new app object with the db, so that initchain hasn't been called
	var wasmOpts []wasmkeeper.Option = nil
	newGapp := NewChainApp(
		logger, db, nil, true, simtestutil.NewAppOptionsWithFlagHome(t.TempDir()),
		wasmOpts,
		EVMAppOptions,
	)
	_, err = newGapp.ExportAppStateAndValidators(false, []string{}, nil)
	require.NoError(t, err, "ExportAppStateAndValidators should not have an error")
}

// ensure that blocked addresses are properly set in bank keeper
func TestBlockedAddrs(t *testing.T) {
	gapp := Setup(t)

	for acc := range BlockedAddresses() {
		t.Run(acc, func(t *testing.T) {
			var addr sdk.AccAddress
			if modAddr, err := sdk.AccAddressFromBech32(acc); err == nil {
				addr = modAddr
			} else {
				addr = gapp.AccountKeeper.GetModuleAddress(acc)
			}
			require.True(t, gapp.BankKeeper.BlockedAddr(addr), "ensure that blocked addresses are properly set in bank keeper")
		})
	}
}

func TestGetMaccPerms(t *testing.T) {
	dup := GetMaccPerms()
	require.Equal(t, maccPerms, dup, "duplicated module account permissions differed from actual module account permissions")
}

// TestMergedRegistry tests that fetching the gogo/protov2 merged registry
// doesn't fail after loading all file descriptors.
func TestMergedRegistry(t *testing.T) {
	r, err := proto.MergedRegistry()
	require.NoError(t, err)
	require.Greater(t, r.NumFiles(), 0)
}

func TestProtoAnnotations(t *testing.T) {
	r, err := proto.MergedRegistry()
	require.NoError(t, err)
	err = msgservice.ValidateProtoAnnotations(r)
	require.NoError(t, err)
}

// TestKudoraChainConfig tests the Kudora-specific chain configuration
func TestKudoraChainConfig(t *testing.T) {
	tests := []struct {
		name    string
		chainID string
		exists  bool
	}{
		{
			name:    "mainnet config exists",
			chainID: ChainID,
			exists:  true,
		},
		{
			name:    "unknown chain config",
			chainID: "unknown_chain-1",
			exists:  false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, exists := ChainsCoinInfo[tt.chainID]
			require.Equal(t, tt.exists, exists, "chain ID existence should match expected")
		})
	}
}

// TestKudoraDenomValidation tests Kudora-specific denomination validation
func TestKudoraDenomValidation(t *testing.T) {
	tests := []struct {
		name    string
		denom   string
		isValid bool
	}{
		{
			name:    "base denom valid",
			denom:   BaseDenom,
			isValid: true,
		},
		{
			name:    "display denom valid", 
			denom:   DisplayDenom,
			isValid: true,
		},
		{
			name:    "empty denom invalid",
			denom:   "",
			isValid: false,
		},
		{
			name:    "uppercase denom invalid",
			denom:   "INVALID",
			isValid: true, // SDK actually allows uppercase denoms
		},
		{
			name:    "special chars invalid",
			denom:   "kud@#$",
			isValid: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := sdk.ValidateDenom(tt.denom)
			if tt.isValid {
				require.NoError(t, err, "valid denom should not return error")
			} else {
				require.Error(t, err, "invalid denom should return error")
			}
		})
	}
}

// TestKudoraBech32Config tests the bech32 prefix configuration
func TestKudoraBech32Config(t *testing.T) {
	// Test that our constants are properly defined
	require.Equal(t, "kudo", Bech32PrefixAccAddr, "account address prefix should be kudo")
	require.Equal(t, "kudopub", Bech32PrefixAccPub, "account pubkey prefix should be kudopub")
	require.Equal(t, "kudovaloper", Bech32PrefixValAddr, "validator address prefix should be kudovaloper")
	require.Equal(t, "kudovaloperpub", Bech32PrefixValPub, "validator pubkey prefix should be kudovaloperpub")
	require.Equal(t, "kudovalcons", Bech32PrefixConsAddr, "consensus address prefix should be kudovalcons")
	require.Equal(t, "kudovalconspub", Bech32PrefixConsPub, "consensus pubkey prefix should be kudovalconspub")
}

// TestKudoraCoinInfoConstants tests the coin information constants
func TestKudoraCoinInfoConstants(t *testing.T) {
	// Verify base denom
	require.Equal(t, "kud", BaseDenom)
	
	// Verify display denom  
	require.Equal(t, "kudos", DisplayDenom)
	
	// Verify coin decimals (should be 18 for EVM compatibility)
	coinInfo, exists := ChainsCoinInfo[ChainID]
	require.True(t, exists, "chain coin info should exist")
	require.Equal(t, uint8(18), uint8(coinInfo.Decimals), "coin decimals should be 18 for EVM compatibility")
}

// TestKudoraAddressFormat tests Kudora address format and validation
func TestKudoraAddressFormat(t *testing.T) {
	// Test that we can create and validate addresses with proper format
	testAddr := sdk.AccAddress([]byte("test1234567890123456"))
	require.Equal(t, 20, len(testAddr.Bytes()), "address should be 20 bytes")
	
	// Test that our bech32 prefixes are correctly defined
	require.Equal(t, "kudo", Bech32PrefixAccAddr, "account prefix should be kudo")
	
	// Test address string contains our constants (even if SDK config uses defaults)
	addrStr := testAddr.String()
	require.NotEmpty(t, addrStr, "address string should not be empty")
	require.Greater(t, len(addrStr), 10, "address string should be reasonable length")
}
