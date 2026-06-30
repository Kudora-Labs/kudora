package app

import (
	"os"
	"sync"
	"testing"

	wasmtypes "github.com/CosmWasm/wasmd/x/wasm/types"
	cmtproto "github.com/cometbft/cometbft/proto/tendermint/types"
	dbm "github.com/cosmos/cosmos-db"
	clientflags "github.com/cosmos/cosmos-sdk/client/flags"
	evmserverflags "github.com/cosmos/evm/server/flags"
	erc20types "github.com/cosmos/evm/x/erc20/types"
	feemarkettypes "github.com/cosmos/evm/x/feemarket/types"
	evmtypes "github.com/cosmos/evm/x/vm/types"
	"github.com/ethereum/go-ethereum/common"

	"cosmossdk.io/log/v2"
	sdkmath "cosmossdk.io/math"

	"github.com/cosmos/cosmos-sdk/baseapp"
	sdk "github.com/cosmos/cosmos-sdk/types"
	banktypes "github.com/cosmos/cosmos-sdk/x/bank/types"
	"github.com/spf13/viper"
	"github.com/stretchr/testify/require"
)

var (
	testAppOnce sync.Once
	testApp     *App
)

func TestKudoraRuntimeDefaults(t *testing.T) {
	t.Helper()

	require.Equal(t, DefaultBaseDenom, sdk.DefaultBondDenom)
	require.Equal(t, sdkmath.NewIntWithDecimal(1, int(DefaultDenomDecimals)), sdk.DefaultPowerReduction)
	require.Equal(t, uint64(120001), DefaultEVMChainID)
	require.Equal(t, "0x1d4c1", ExpectedEthChainIDHex)
}

func TestWasmAddressVerifierAllowsAccountAndContractLengths(t *testing.T) {
	t.Helper()

	require.NoError(t, sdk.VerifyAddressFormat(make([]byte, 20)))
	require.NoError(t, sdk.VerifyAddressFormat(make([]byte, 32)))
	require.Error(t, sdk.VerifyAddressFormat(make([]byte, 21)))
}

func TestDefaultGenesisUsesKudoraDenomMetadata(t *testing.T) {
	t.Helper()

	app := newTestApp(t)
	genesis := app.DefaultGenesis()

	var bankGenesis banktypes.GenesisState
	require.NoError(t, app.AppCodec().UnmarshalJSON(genesis[banktypes.ModuleName], &bankGenesis))
	require.Len(t, bankGenesis.DenomMetadata, 1)

	metadata := bankGenesis.DenomMetadata[0]
	require.Equal(t, DefaultBaseDenom, metadata.Base)
	require.Equal(t, DefaultDisplayDenom, metadata.Display)
	require.Equal(t, DefaultDenomSymbol, metadata.Symbol)
	require.Len(t, metadata.DenomUnits, 2)
	require.EqualValues(t, DefaultDenomDecimals, metadata.DenomUnits[1].Exponent)

	var evmGenesis evmtypes.GenesisState
	require.NoError(t, app.AppCodec().UnmarshalJSON(genesis[evmtypes.ModuleName], &evmGenesis))
	require.Equal(t, DefaultBaseDenom, evmGenesis.Params.EvmDenom)
	require.Equal(t, kudoraActiveStaticPrecompiles(), evmGenesis.Params.ActiveStaticPrecompiles)

	var feeMarketGenesis feemarkettypes.GenesisState
	require.NoError(t, app.AppCodec().UnmarshalJSON(genesis[feemarkettypes.ModuleName], &feeMarketGenesis))
	require.True(t, feeMarketGenesis.Params.NoBaseFee)

	var erc20Genesis erc20types.GenesisState
	require.NoError(t, app.AppCodec().UnmarshalJSON(genesis[erc20types.ModuleName], &erc20Genesis))
	require.Empty(t, erc20Genesis.TokenPairs)
	require.Empty(t, erc20Genesis.NativePrecompiles)

	var wasmGenesis wasmtypes.GenesisState
	require.NoError(t, app.AppCodec().UnmarshalJSON(genesis[wasmtypes.ModuleName], &wasmGenesis))
	require.Equal(t, wasmtypes.AllowNobody.Permission, wasmGenesis.Params.CodeUploadAccess.Permission)
	require.Empty(t, wasmGenesis.Params.CodeUploadAccess.Addresses)
	require.Equal(t, wasmtypes.AccessTypeNobody, wasmGenesis.Params.InstantiateDefaultPermission)
}

func TestStaticPrecompileSurfaceRemainsNarrow(t *testing.T) {
	t.Helper()

	require.Equal(t, []string{
		evmtypes.P256PrecompileAddress,
		evmtypes.Bech32PrecompileAddress,
	}, kudoraActiveStaticPrecompiles())

	precompiles := kudoraStaticPrecompiles()
	for _, forbidden := range []string{
		evmtypes.StakingPrecompileAddress,
		evmtypes.DistributionPrecompileAddress,
		evmtypes.ICS20PrecompileAddress,
		evmtypes.BankPrecompileAddress,
		evmtypes.GovPrecompileAddress,
		evmtypes.SlashingPrecompileAddress,
		evmtypes.ICS02PrecompileAddress,
	} {
		_, found := precompiles[common.HexToAddress(forbidden)]
		require.Falsef(t, found, "unexpected stateful precompile enabled: %s", forbidden)
	}
}

func TestInitGenesisStoresEvmCoinInfoWith18Decimals(t *testing.T) {
	t.Helper()

	app := newTestApp(t)
	ctx := app.NewUncachedContext(false, cmtproto.Header{ChainID: DefaultChainID})
	app.BankKeeper.SetDenomMetaData(ctx, kudoraBankMetadata())
	require.NoError(t, app.EVMKeeper.SetParams(ctx, NewEVMGenesisState().Params))
	require.NoError(t, app.EVMKeeper.InitEvmCoinInfo(ctx))

	coinInfo := app.EVMKeeper.GetEvmCoinInfo(ctx)
	require.Equal(t, DefaultBaseDenom, coinInfo.Denom)
	require.Equal(t, DefaultBaseDenom, coinInfo.ExtendedDenom)
	require.Equal(t, DefaultDisplayDenom, coinInfo.DisplayDenom)
	require.EqualValues(t, DefaultDenomDecimals, coinInfo.Decimals)
}

func TestExplicitEVMChainIDOptionDoesNotDrift(t *testing.T) {
	t.Helper()

	opts := viper.New()
	opts.Set(evmserverflags.EVMChainID, DefaultEVMChainID)
	app := newTestApp(t)

	require.Equal(t, DefaultEVMChainID, defaultEVMChainID(opts))
	require.NotNil(t, app.EVMKeeper)
	require.NotNil(t, app.IBCKeeper)
	require.NotNil(t, app.TxConfig())
}

func newTestApp(t *testing.T) *App {
	t.Helper()

	testAppOnce.Do(func() {
		homeDir, err := os.MkdirTemp("", "kudora-app-tests-")
		require.NoError(t, err)

		opts := viper.New()
		opts.Set(evmserverflags.EVMChainID, DefaultEVMChainID)
		opts.Set(clientflags.FlagHome, homeDir)

		testApp = New(
			log.NewNopLogger(),
			dbm.NewMemDB(),
			nil,
			true,
			opts,
			baseapp.SetChainID(DefaultChainID),
		)
	})

	require.NotNil(t, testApp)
	return testApp
}
