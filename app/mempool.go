package app

import (
	evmmempool "github.com/cosmos/evm/mempool"
	cosmosevmserver "github.com/cosmos/evm/server"
	evmtypes "github.com/cosmos/evm/x/vm/types"

	"cosmossdk.io/log/v2"

	"github.com/cosmos/cosmos-sdk/baseapp"
	servertypes "github.com/cosmos/cosmos-sdk/server/types"
	sdk "github.com/cosmos/cosmos-sdk/types"
)

// configureEVMMempool sets up the upstream Cosmos EVM mempool and proposal handlers.
func (app *App) configureEVMMempool(appOpts servertypes.AppOptions, logger log.Logger) error {
	if evmtypes.GetChainConfig() == nil {
		logger.Debug("evm chain config is not set, skipping mempool configuration")
		return nil
	}

	mpConfig := cosmosevmserver.ResolveMempoolConfig(app.GetAnteHandler(), appOpts, logger)
	txEncoder := evmmempool.NewTxEncoder(app.txConfig)
	evmRechecker := evmmempool.NewTxRechecker(mpConfig.AnteHandler, txEncoder)
	cosmosRechecker := evmmempool.NewTxRechecker(mpConfig.AnteHandler, txEncoder)
	cosmosPoolMaxTx := cosmosevmserver.GetCosmosPoolMaxTx(appOpts, logger)
	checkTxTimeout := cosmosevmserver.GetMempoolCheckTxTimeout(appOpts, logger)

	if cosmosPoolMaxTx < 0 {
		logger.Debug("evm mempool is disabled, skipping configuration")
		return nil
	}

	if err := cosmosevmserver.ValidateReapBounds(appOpts, mpConfig.BlockGasLimit); err != nil {
		return err
	}

	mempool := evmmempool.NewMempool(
		app.CreateQueryContext,
		logger,
		app.EVMKeeper,
		app.FeeMarketKeeper,
		app.txConfig,
		evmRechecker,
		cosmosRechecker,
		mpConfig,
		cosmosPoolMaxTx,
	)

	app.EVMMempool = mempool

	prepareProposalHandler := baseapp.
		NewDefaultProposalHandler(mempool, NewNoCheckProposalTxVerifier(app.BaseApp)).
		PrepareProposalHandler()

	app.SetPrepareProposal(prepareProposalHandler)
	app.SetInsertTxHandler(mempool.NewInsertTxHandler(app.TxDecode))
	app.SetReapTxsHandler(mempool.NewReapTxsHandler())
	app.SetCheckTxHandler(mempool.NewCheckTxHandler(app.TxDecode, checkTxTimeout))
	app.SetMempool(mempool)

	app.SetPrepareCheckStater(func(_ sdk.Context) {
		if !mempool.HasEventBus() {
			mempool.NotifyNewBlock()
		}
	})

	return nil
}
