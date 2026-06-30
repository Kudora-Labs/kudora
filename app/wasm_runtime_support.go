package app

import (
	wasmvmtypes "github.com/CosmWasm/wasmvm/v3/types"

	errorsmod "cosmossdk.io/errors"

	sdk "github.com/cosmos/cosmos-sdk/types"

	wasmkeeper "github.com/CosmWasm/wasmd/x/wasm/keeper"
	wasmtypes "github.com/CosmWasm/wasmd/x/wasm/types"
)

type disabledTransferPortSource struct{}

func (disabledTransferPortSource) GetPort(sdk.Context) string {
	return ""
}

func kudoraWasmKeeperOptions() []wasmkeeper.Option {
	return []wasmkeeper.Option{
		wasmkeeper.WithMessageEncoders(&wasmkeeper.MessageEncoders{
			IBC:  disabledWasmIBCEncoder,
			IBC2: disabledWasmIBCv2Encoder,
		}),
		wasmkeeper.WithQueryPlugins(&wasmkeeper.QueryPlugins{
			IBC: disabledWasmIBCQuerier,
		}),
	}
}

func disabledWasmIBCEncoder(
	_ sdk.Context,
	_ sdk.AccAddress,
	_ string,
	_ *wasmvmtypes.IBCMsg,
) ([]sdk.Msg, error) {
	return nil, errorsmod.Wrap(wasmtypes.ErrUnsupportedForContract, "IBC contract messages are disabled in Kudora Phase 5 runtime")
}

func disabledWasmIBCv2Encoder(
	_ sdk.AccAddress,
	_ *wasmvmtypes.IBC2Msg,
) ([]sdk.Msg, error) {
	return nil, errorsmod.Wrap(wasmtypes.ErrUnsupportedForContract, "IBC v2 contract messages are disabled in Kudora Phase 5 runtime")
}

func disabledWasmIBCQuerier(
	_ sdk.Context,
	_ sdk.AccAddress,
	_ *wasmvmtypes.IBCQuery,
) ([]byte, error) {
	return nil, errorsmod.Wrap(wasmtypes.ErrUnsupportedForContract, "IBC contract queries are disabled in Kudora Phase 5 runtime")
}
