package cmd

import (
	"errors"
	"os"

	"github.com/spf13/cobra"
	"github.com/spf13/viper"

	dbm "github.com/cosmos/cosmos-db"
	cosmosevmhd "github.com/cosmos/evm/crypto/hd"
	srvflags "github.com/cosmos/evm/server/flags"
	evmtypes "github.com/cosmos/evm/x/vm/types"

	"cosmossdk.io/log/v2"
	"github.com/cosmos/cosmos-sdk/client"
	clientcfg "github.com/cosmos/cosmos-sdk/client/config"
	"github.com/cosmos/cosmos-sdk/client/flags"
	"github.com/cosmos/cosmos-sdk/codec"
	codectypes "github.com/cosmos/cosmos-sdk/codec/types"
	sdkserver "github.com/cosmos/cosmos-sdk/server"
	sdktestutil "github.com/cosmos/cosmos-sdk/types/module/testutil"
	"github.com/cosmos/cosmos-sdk/types/tx/signing"
	"github.com/cosmos/cosmos-sdk/version"
	"github.com/cosmos/cosmos-sdk/x/auth/tx"
	txmodule "github.com/cosmos/cosmos-sdk/x/auth/tx/config"
	authtypes "github.com/cosmos/cosmos-sdk/x/auth/types"

	"github.com/Kudora-Labs/kudora/app"
)

// NewRootCmd creates the root command for kudorad.
func NewRootCmd() *cobra.Command {
	version.Name = app.Name
	version.AppName = app.Name + "d"

	tempAppHome, err := os.MkdirTemp("", "kudorad-root-")
	if err != nil {
		panic(err)
	}
	defer os.RemoveAll(tempAppHome)

	tempAppOpts := viper.New()
	tempAppOpts.Set(flags.FlagHome, tempAppHome)
	tempAppOpts.Set(srvflags.EVMChainID, evmtypes.DefaultEVMChainID)

	tempApp := app.New(
		log.NewNopLogger(),
		dbm.NewMemDB(),
		nil,
		false,
		tempAppOpts,
	)

	encodingConfig := sdktestutil.TestEncodingConfig{
		InterfaceRegistry: tempApp.InterfaceRegistry(),
		Codec:             tempApp.AppCodec(),
		TxConfig:          tempApp.TxConfig(),
		Amino:             tempApp.LegacyAmino(),
	}

	initClientCtx := client.Context{}.
		WithCodec(encodingConfig.Codec).
		WithInterfaceRegistry(encodingConfig.InterfaceRegistry).
		WithTxConfig(encodingConfig.TxConfig).
		WithLegacyAmino(encodingConfig.Amino).
		WithInput(os.Stdin).
		WithAccountRetriever(authtypes.AccountRetriever{}).
		WithBroadcastMode(flags.BroadcastSync).
		WithHomeDir(app.DefaultNodeHome).
		WithViper("").
		WithKeyringOptions(cosmosevmhd.EthSecp256k1Option()).
		WithLedgerHasProtobuf(true)

	rootCmd := &cobra.Command{
		Use:   app.Name + "d",
		Short: "kudora node",
		PersistentPreRunE: func(cmd *cobra.Command, _ []string) error {
			cmd.SetOut(cmd.OutOrStdout())
			cmd.SetErr(cmd.ErrOrStderr())

			initClientCtx = initClientCtx.WithCmdContext(cmd.Context())

			var err error
			initClientCtx, err = client.ReadPersistentCommandFlags(initClientCtx, cmd.Flags())
			if err != nil {
				return err
			}

			initClientCtx, err = clientcfg.ReadFromClientConfig(initClientCtx)
			if err != nil {
				var configNotFound viper.ConfigFileNotFoundError
				if !errors.As(err, &configNotFound) {
					return err
				}
			}

			if !initClientCtx.Offline {
				enabledSignModes := append(tx.DefaultSignModes, signing.SignMode_SIGN_MODE_TEXTUAL) //nolint:gocritic
				txConfigOpts := tx.ConfigOptions{
					EnabledSignModes:           enabledSignModes,
					TextualCoinMetadataQueryFn: txmodule.NewGRPCCoinMetadataQueryFn(initClientCtx),
				}
				txConfig, err := tx.NewTxConfigWithOptions(initClientCtx.Codec, txConfigOpts)
				if err != nil {
					return err
				}
				initClientCtx = initClientCtx.WithTxConfig(txConfig)
			}

			if err := client.SetCmdClientContextHandler(initClientCtx, cmd); err != nil {
				return err
			}

			customAppTemplate, customAppConfig := initAppConfig()
			customCMTConfig := initCometBFTConfig()
			return sdkserver.InterceptConfigsPreRunHandler(cmd, customAppTemplate, customAppConfig, customCMTConfig)
		},
	}

	initRootCmd(rootCmd, tempApp)

	return rootCmd
}

// ProvideClientContext remains available for tests and command helpers that expect a wired client context.
func ProvideClientContext(
	appCodec codec.Codec,
	interfaceRegistry codectypes.InterfaceRegistry,
	txConfigOpts tx.ConfigOptions,
	legacyAmino *codec.LegacyAmino,
) client.Context {
	clientCtx := client.Context{}.
		WithCodec(appCodec).
		WithInterfaceRegistry(interfaceRegistry).
		WithLegacyAmino(legacyAmino).
		WithInput(os.Stdin).
		WithAccountRetriever(authtypes.AccountRetriever{}).
		WithHomeDir(app.DefaultNodeHome).
		WithViper("").
		WithKeyringOptions(cosmosevmhd.EthSecp256k1Option()).
		WithLedgerHasProtobuf(true)

	if configuredClientCtx, err := clientcfg.ReadFromClientConfig(clientCtx); err == nil {
		clientCtx = configuredClientCtx
	}

	txConfigOpts.TextualCoinMetadataQueryFn = txmodule.NewGRPCCoinMetadataQueryFn(clientCtx)
	txCfg, err := tx.NewTxConfigWithOptions(clientCtx.Codec, txConfigOpts)
	if err != nil {
		panic(err)
	}

	return clientCtx.WithTxConfig(txCfg)
}
