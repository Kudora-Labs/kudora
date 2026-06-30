package cmd

import (
	wasmtypes "github.com/CosmWasm/wasmd/x/wasm/types"
	cmtcfg "github.com/cometbft/cometbft/config"
	serverconfig "github.com/cosmos/cosmos-sdk/server/config"
	cosmosevmserverconfig "github.com/cosmos/evm/server/config"

	"github.com/Kudora-Labs/kudora/app"
)

func initCometBFTConfig() *cmtcfg.Config {
	cfg := cmtcfg.DefaultConfig()
	cfg.Mempool.Type = "app"
	return cfg
}

func initAppConfig() (string, interface{}) {
	srvCfg := serverconfig.DefaultConfig()
	srvCfg.MinGasPrices = "0" + app.DefaultBaseDenom

	evmCfg := cosmosevmserverconfig.DefaultEVMConfig()
	evmCfg.EVMChainID = app.DefaultEVMChainID

	jsonRPCCfg := cosmosevmserverconfig.DefaultJSONRPCConfig()
	jsonRPCCfg.Enable = false
	jsonRPCCfg.Address = "127.0.0.1:8545"
	jsonRPCCfg.WsAddress = "127.0.0.1:8546"

	customAppConfig := struct {
		serverconfig.Config `mapstructure:",squash"`
		EVM                 cosmosevmserverconfig.EVMConfig     `mapstructure:"evm"`
		JSONRPC             cosmosevmserverconfig.JSONRPCConfig `mapstructure:"json-rpc"`
		TLS                 cosmosevmserverconfig.TLSConfig     `mapstructure:"tls"`
		Wasm                wasmtypes.NodeConfig                `mapstructure:"wasm"`
	}{
		Config:  *srvCfg,
		EVM:     *evmCfg,
		JSONRPC: *jsonRPCCfg,
		TLS:     *cosmosevmserverconfig.DefaultTLSConfig(),
		Wasm:    wasmtypes.DefaultNodeConfig(),
	}

	return serverconfig.DefaultConfigTemplate +
		cosmosevmserverconfig.DefaultEVMConfigTemplate +
		wasmtypes.DefaultConfigTemplate(), customAppConfig
}
