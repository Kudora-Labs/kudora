package cmd

import (
	"errors"
	"io"

	"github.com/CosmWasm/wasmd/x/wasm"
	wasmcli "github.com/CosmWasm/wasmd/x/wasm/client/cli"
	"github.com/spf13/cast"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"

	cmtcli "github.com/cometbft/cometbft/libs/cli"

	dbm "github.com/cosmos/cosmos-db"
	cosmosevmcmd "github.com/cosmos/evm/client"
	evmdebug "github.com/cosmos/evm/client/debug"
	cosmosevmserver "github.com/cosmos/evm/server"
	srvflags "github.com/cosmos/evm/server/flags"
	"github.com/cosmos/evm/utils"

	"cosmossdk.io/log/v2"
	confixcmd "cosmossdk.io/tools/confix/cmd"
	"github.com/cosmos/cosmos-sdk/store/v2"
	snapshottypes "github.com/cosmos/cosmos-sdk/store/v2/snapshots/types"
	storetypes "github.com/cosmos/cosmos-sdk/store/v2/types"

	"github.com/cosmos/cosmos-sdk/baseapp"
	"github.com/cosmos/cosmos-sdk/client"
	"github.com/cosmos/cosmos-sdk/client/flags"
	"github.com/cosmos/cosmos-sdk/client/pruning"
	"github.com/cosmos/cosmos-sdk/client/rpc"
	"github.com/cosmos/cosmos-sdk/client/snapshot"
	sdkserver "github.com/cosmos/cosmos-sdk/server"
	servertypes "github.com/cosmos/cosmos-sdk/server/types"
	authcmd "github.com/cosmos/cosmos-sdk/x/auth/client/cli"
	banktypes "github.com/cosmos/cosmos-sdk/x/bank/types"
	genutilcli "github.com/cosmos/cosmos-sdk/x/genutil/client/cli"

	"github.com/Kudora-Labs/kudora/app"
	integritycli "github.com/Kudora-Labs/kudora/x/integrity/client/cli"
)

func initRootCmd(rootCmd *cobra.Command, tempApp *app.App) {
	sdkAppCreator := func(logger log.Logger, db dbm.DB, appOpts servertypes.AppOptions) servertypes.Application {
		return newApp(logger, db, nil, appOpts)
	}

	rootCmd.AddCommand(
		NewInitCmd(tempApp, tempApp.BasicModuleManager),
		NewInPlaceTestnetCmd(),
		NewTestnetMultiNodeCmd(tempApp.BasicModuleManager, banktypes.GenesisBalancesIterator{}),
		genutilcli.Commands(tempApp.TxConfig(), tempApp.BasicModuleManager, app.DefaultNodeHome),
		cmtcli.NewCompletionCmd(rootCmd, true),
		evmdebug.Cmd(),
		confixcmd.ConfigCommand(),
		pruning.Cmd(sdkAppCreator, app.DefaultNodeHome),
		snapshot.Cmd(sdkAppCreator),
	)

	cosmosevmserver.AddCommands(
		rootCmd,
		cosmosevmserver.NewDefaultStartOptions(newEVMApp, app.DefaultNodeHome),
		appExport,
		addModuleInitFlags,
	)
	wasmcli.ExtendUnsafeResetAllCmd(rootCmd)

	rootCmd.AddCommand(
		cosmosevmcmd.KeyCommands(app.DefaultNodeHome, true),
		sdkserver.StatusCommand(),
		queryCommand(),
		txCommand(),
	)

	if _, err := srvflags.AddTxFlags(rootCmd); err != nil {
		panic(err)
	}
}

func addModuleInitFlags(startCmd *cobra.Command) {
	wasm.AddModuleInitFlags(startCmd)
}

func queryCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:                        "query",
		Aliases:                    []string{"q"},
		Short:                      "Querying subcommands",
		DisableFlagParsing:         false,
		SuggestionsMinimumDistance: 2,
		RunE:                       client.ValidateCmd,
	}

	cmd.AddCommand(
		rpc.QueryEventForTxCmd(),
		rpc.ValidatorCommand(),
		authcmd.QueryTxsByEventsCmd(),
		authcmd.QueryTxCmd(),
		sdkserver.QueryBlockCmd(),
		sdkserver.QueryBlockResultsCmd(),
	)
	cmd.AddCommand(wasm.AppModuleBasic{}.GetQueryCmd())
	cmd.AddCommand(integritycli.GetQueryCmd())

	cmd.PersistentFlags().String(flags.FlagChainID, "", "The network chain ID")
	return cmd
}

func txCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:                        "tx",
		Short:                      "Transactions subcommands",
		DisableFlagParsing:         false,
		SuggestionsMinimumDistance: 2,
		RunE:                       client.ValidateCmd,
	}

	cmd.AddCommand(
		authcmd.GetSignCommand(),
		authcmd.GetSignBatchCommand(),
		authcmd.GetMultiSignCommand(),
		authcmd.GetMultiSignBatchCmd(),
		authcmd.GetValidateSignaturesCommand(),
		authcmd.GetBroadcastCommand(),
		authcmd.GetEncodeCommand(),
		authcmd.GetDecodeCommand(),
		authcmd.GetSimulateCmd(),
	)
	cmd.AddCommand(wasm.AppModuleBasic{}.GetTxCmd())
	cmd.AddCommand(integritycli.GetTxCmd())

	cmd.PersistentFlags().String(flags.FlagChainID, "", "The network chain ID")
	return cmd
}

func newApp(
	logger log.Logger,
	db dbm.DB,
	traceStore io.Writer,
	appOpts servertypes.AppOptions,
) servertypes.Application {
	chainID, err := getChainIDFromOpts(appOpts)
	if err != nil {
		panic(err)
	}

	baseAppOptions := newBaseAppOptions(appOpts, chainID)
	return app.New(logger, db, traceStore, true, appOpts, baseAppOptions...)
}

func newEVMApp(
	logger log.Logger,
	db dbm.DB,
	appOpts servertypes.AppOptions,
) cosmosevmserver.Application {
	created := newApp(logger, db, nil, appOpts)
	evmApp, ok := created.(*app.App)
	if !ok {
		panic("newApp did not return *app.App")
	}
	return evmApp
}

func newBaseAppOptions(appOpts servertypes.AppOptions, chainID string) []func(*baseapp.BaseApp) {
	var cache storetypes.MultiStorePersistentCache
	if cast.ToBool(appOpts.Get(sdkserver.FlagInterBlockCache)) {
		cache = store.NewCommitKVStoreCacheManager()
	}

	pruningOpts, err := sdkserver.GetPruningOptionsFromFlags(appOpts)
	if err != nil {
		panic(err)
	}

	snapshotStore, err := sdkserver.GetSnapshotStore(appOpts)
	if err != nil {
		panic(err)
	}

	snapshotOptions := snapshottypes.NewSnapshotOptions(
		cast.ToUint64(appOpts.Get(sdkserver.FlagStateSyncSnapshotInterval)),
		cast.ToUint32(appOpts.Get(sdkserver.FlagStateSyncSnapshotKeepRecent)),
	)

	return []func(*baseapp.BaseApp){
		baseapp.SetPruning(pruningOpts),
		baseapp.SetMinGasPrices(cast.ToString(appOpts.Get(sdkserver.FlagMinGasPrices))),
		baseapp.SetQueryGasLimit(cast.ToUint64(appOpts.Get(sdkserver.FlagQueryGasLimit))),
		baseapp.SetHaltHeight(cast.ToUint64(appOpts.Get(sdkserver.FlagHaltHeight))),
		baseapp.SetHaltTime(cast.ToUint64(appOpts.Get(sdkserver.FlagHaltTime))),
		baseapp.SetMinRetainBlocks(cast.ToUint64(appOpts.Get(sdkserver.FlagMinRetainBlocks))),
		baseapp.SetInterBlockCache(cache),
		baseapp.SetTrace(cast.ToBool(appOpts.Get(sdkserver.FlagTrace))),
		baseapp.SetIndexEvents(cast.ToStringSlice(appOpts.Get(sdkserver.FlagIndexEvents))),
		baseapp.SetSnapshot(snapshotStore, snapshotOptions),
		baseapp.SetIAVLCacheSize(cast.ToInt(appOpts.Get(sdkserver.FlagIAVLCacheSize))),
		baseapp.SetIAVLDisableFastNode(cast.ToBool(appOpts.Get(sdkserver.FlagDisableIAVLFastNode))),
		baseapp.SetChainID(chainID),
	}
}

func appExport(
	logger log.Logger,
	db dbm.DB,
	height int64,
	forZeroHeight bool,
	jailAllowedAddrs []string,
	appOpts servertypes.AppOptions,
	modulesToExport []string,
) (servertypes.ExportedApp, error) {
	homePath, ok := appOpts.Get(flags.FlagHome).(string)
	if !ok || homePath == "" {
		return servertypes.ExportedApp{}, errors.New("application home not set")
	}

	viperAppOpts, ok := appOpts.(*viper.Viper)
	if !ok {
		return servertypes.ExportedApp{}, errors.New("appOpts is not viper.Viper")
	}

	viperAppOpts.Set(sdkserver.FlagInvCheckPeriod, 1)
	appOpts = viperAppOpts

	chainID, err := getChainIDFromOpts(appOpts)
	if err != nil {
		return servertypes.ExportedApp{}, err
	}

	baseAppOptions := newBaseAppOptions(appOpts, chainID)

	var kudoraApp *app.App
	if height != -1 {
		kudoraApp = app.New(logger, db, nil, false, appOpts, baseAppOptions...)
		if err := kudoraApp.LoadHeight(height); err != nil {
			return servertypes.ExportedApp{}, err
		}
	} else {
		kudoraApp = app.New(logger, db, nil, true, appOpts, baseAppOptions...)
	}

	return kudoraApp.ExportAppStateAndValidators(forZeroHeight, jailAllowedAddrs, modulesToExport)
}

func getChainIDFromOpts(appOpts servertypes.AppOptions) (string, error) {
	chainID := cast.ToString(appOpts.Get(flags.FlagChainID))
	if chainID != "" {
		return chainID, nil
	}

	homeDir := cast.ToString(appOpts.Get(flags.FlagHome))
	if homeDir == "" {
		homeDir = app.DefaultNodeHome
	}

	return utils.GetChainIDFromHome(homeDir)
}
