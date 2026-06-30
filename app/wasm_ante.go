package app

import (
	"errors"

	wasmkeeper "github.com/CosmWasm/wasmd/x/wasm/keeper"
	wasmtypes "github.com/CosmWasm/wasmd/x/wasm/types"
	evmante "github.com/cosmos/evm/ante"
	evmcosmosante "github.com/cosmos/evm/ante/cosmos"
	evmevmante "github.com/cosmos/evm/ante/evm"
	evmantetypes "github.com/cosmos/evm/ante/types"
	evmtypes "github.com/cosmos/evm/x/vm/types"
	"github.com/cosmos/gogoproto/proto"
	ibcante "github.com/cosmos/ibc-go/v11/modules/core/ante"

	corestoretypes "cosmossdk.io/core/store"

	sdk "github.com/cosmos/cosmos-sdk/types"
	authante "github.com/cosmos/cosmos-sdk/x/auth/ante"
	sdkvesting "github.com/cosmos/cosmos-sdk/x/auth/vesting/types"
)

type WasmAwareAnteOptions struct {
	EVM                   evmante.HandlerOptions
	NodeConfig            *wasmtypes.NodeConfig
	WasmKeeper            *wasmkeeper.Keeper
	TXCounterStoreService corestoretypes.KVStoreService
}

func (options WasmAwareAnteOptions) Validate() error {
	if err := options.EVM.Validate(); err != nil {
		return err
	}
	if options.NodeConfig == nil {
		return errors.New("wasm config is required for ante handler")
	}
	if options.WasmKeeper == nil {
		return errors.New("wasm keeper is required for ante handler")
	}
	if options.TXCounterStoreService == nil {
		return errors.New("wasm tx counter store service is required for ante handler")
	}
	return nil
}

func NewWasmAwareAnteHandler(options WasmAwareAnteOptions) (sdk.AnteHandler, error) {
	if err := options.Validate(); err != nil {
		return nil, err
	}

	extensionOptionsEthereumTx := "/" + proto.MessageName(&evmtypes.ExtensionOptionsEthereumTx{})
	extensionOptionsDynamicFeeTx := "/" + proto.MessageName(&evmantetypes.ExtensionOptionDynamicFeeTx{})

	return func(ctx sdk.Context, tx sdk.Tx, sim bool) (sdk.Context, error) {
		if txWithExtensions, ok := tx.(authante.HasExtensionOptionsTx); ok {
			opts := txWithExtensions.GetExtensionOptions()
			if len(opts) > 0 {
				switch opts[0].GetTypeUrl() {
				case extensionOptionsEthereumTx:
					return newKudoraEVMAnteHandler(ctx, options.EVM)(ctx, tx, sim)
				case extensionOptionsDynamicFeeTx:
					return newKudoraCosmosAnteHandler(
						ctx,
						options.EVM,
						*options.NodeConfig,
						options.WasmKeeper,
						options.TXCounterStoreService,
					)(ctx, tx, sim)
				default:
					return ctx, errors.New("unsupported extension option")
				}
			}
		}

		return newKudoraCosmosAnteHandler(
			ctx,
			options.EVM,
			*options.NodeConfig,
			options.WasmKeeper,
			options.TXCounterStoreService,
		)(ctx, tx, sim)
	}, nil
}

func newKudoraEVMAnteHandler(ctx sdk.Context, options evmante.HandlerOptions) sdk.AnteHandler {
	evmParams := options.EvmKeeper.GetParams(ctx)
	feemarketParams := options.FeeMarketKeeper.GetParams(ctx)

	return sdk.ChainAnteDecorators(
		evmevmante.NewEVMMonoDecorator(
			options.AccountKeeper,
			options.FeeMarketKeeper,
			options.EvmKeeper,
			options.MaxTxGasWanted,
			&evmParams,
			&feemarketParams,
		),
		evmante.NewTxListenerDecorator(options.PendingTxListener),
	)
}

func newKudoraCosmosAnteHandler(
	ctx sdk.Context,
	options evmante.HandlerOptions,
	nodeConfig wasmtypes.NodeConfig,
	wasmKeeper *wasmkeeper.Keeper,
	txCounterStoreService corestoretypes.KVStoreService,
) sdk.AnteHandler {
	feemarketParams := options.FeeMarketKeeper.GetParams(ctx)
	var txFeeChecker authante.TxFeeChecker
	if options.DynamicFeeChecker {
		txFeeChecker = evmevmante.NewDynamicFeeChecker(&feemarketParams)
	}

	return sdk.ChainAnteDecorators(
		evmcosmosante.NewRejectMessagesDecorator(),
		evmcosmosante.NewAuthzLimiterDecorator(
			sdk.MsgTypeURL(&evmtypes.MsgEthereumTx{}),
			sdk.MsgTypeURL(&sdkvesting.MsgCreateVestingAccount{}),
		),
		authante.NewSetUpContextDecorator(),
		wasmkeeper.NewLimitSimulationGasDecorator(nodeConfig.SimulationGasLimit),
		wasmkeeper.NewCountTXDecorator(txCounterStoreService),
		wasmkeeper.NewGasRegisterDecorator(wasmKeeper.GetGasRegister()),
		wasmkeeper.NewTxContractsDecorator(),
		authante.NewExtensionOptionsDecorator(options.ExtensionOptionChecker),
		authante.NewValidateBasicDecorator(),
		authante.NewTxTimeoutHeightDecorator(),
		authante.NewValidateMemoDecorator(options.AccountKeeper),
		evmcosmosante.NewMinGasPriceDecorator(&feemarketParams),
		authante.NewConsumeGasForTxSizeDecorator(options.AccountKeeper),
		authante.NewDeductFeeDecorator(options.AccountKeeper, options.BankKeeper, options.FeegrantKeeper, txFeeChecker),
		authante.NewSetPubKeyDecorator(options.AccountKeeper),
		authante.NewValidateSigCountDecorator(options.AccountKeeper),
		authante.NewSigGasConsumeDecorator(options.AccountKeeper, options.SigGasConsumer),
		authante.NewSigVerificationDecorator(options.AccountKeeper, options.SignModeHandler),
		authante.NewIncrementSequenceDecorator(options.AccountKeeper),
		ibcante.NewRedundantRelayDecorator(options.IBCKeeper),
	)
}
