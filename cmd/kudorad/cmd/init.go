package cmd

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"

	cfg "github.com/cometbft/cometbft/config"
	tmed25519 "github.com/cometbft/cometbft/crypto/ed25519"
	"github.com/cometbft/cometbft/p2p"
	"github.com/cometbft/cometbft/privval"
	cmttypes "github.com/cometbft/cometbft/types"
	"github.com/cosmos/go-bip39"
	"github.com/spf13/cobra"

	errorsmod "cosmossdk.io/errors"

	"github.com/cosmos/cosmos-sdk/client"
	"github.com/cosmos/cosmos-sdk/client/flags"
	"github.com/cosmos/cosmos-sdk/client/input"
	cryptocodec "github.com/cosmos/cosmos-sdk/crypto/codec"
	"github.com/cosmos/cosmos-sdk/crypto/keys/ed25519"
	cryptotypes "github.com/cosmos/cosmos-sdk/crypto/types"
	"github.com/cosmos/cosmos-sdk/server"
	"github.com/cosmos/cosmos-sdk/telemetry"
	"github.com/cosmos/cosmos-sdk/types/module"
	"github.com/cosmos/cosmos-sdk/version"
	genutilcli "github.com/cosmos/cosmos-sdk/x/genutil/client/cli"
	genutiltypes "github.com/cosmos/cosmos-sdk/x/genutil/types"

	"github.com/Kudora-Labs/kudora/app"
)

type initPrintInfo struct {
	Moniker    string          `json:"moniker" yaml:"moniker"`
	ChainID    string          `json:"chain_id" yaml:"chain_id"`
	NodeID     string          `json:"node_id" yaml:"node_id"`
	GenTxsDir  string          `json:"gentxs_dir" yaml:"gentxs_dir"`
	AppMessage json.RawMessage `json:"app_message" yaml:"app_message"`
}

func initializeNodeValidatorFilesFromMnemonic(config *cfg.Config, mnemonic string) (string, cryptotypes.PubKey, error) {
	if len(mnemonic) > 0 && !bip39.IsMnemonicValid(mnemonic) {
		return "", nil, errors.New("invalid mnemonic")
	}

	nodeKey, err := p2p.LoadOrGenNodeKey(config.NodeKeyFile())
	if err != nil {
		return "", nil, err
	}

	pvKeyFile := config.PrivValidatorKeyFile()
	if err := os.MkdirAll(filepath.Dir(pvKeyFile), 0o777); err != nil {
		return "", nil, fmt.Errorf("could not create directory %q: %w", filepath.Dir(pvKeyFile), err)
	}

	pvStateFile := config.PrivValidatorStateFile()
	if err := os.MkdirAll(filepath.Dir(pvStateFile), 0o777); err != nil {
		return "", nil, fmt.Errorf("could not create directory %q: %w", filepath.Dir(pvStateFile), err)
	}

	var filePV *privval.FilePV
	if mnemonic == "" {
		filePV = privval.LoadOrGenFilePV(pvKeyFile, pvStateFile)
	} else {
		privKey := tmed25519.GenPrivKeyFromSecret([]byte(mnemonic))
		filePV = privval.NewFilePV(privKey, pvKeyFile, pvStateFile)
		filePV.Save()
	}

	tmValPubKey, err := filePV.GetPubKey()
	if err != nil {
		return "", nil, err
	}

	valPubKey, err := cryptocodec.FromCmtPubKeyInterface(tmValPubKey)
	if err != nil {
		return "", nil, err
	}

	return string(nodeKey.ID()), valPubKey, nil
}

func NewInitCmd(kudoraApp *app.App, _ module.BasicManager) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "init [moniker]",
		Short: "Initialize private validator, p2p, genesis, and application configuration files",
		Long:  "Initialize validators's and node's configuration files.",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			clientCtx := client.GetClientContextFromCmd(cmd)
			serverCtx := server.GetServerContextFromCmd(cmd)
			config := serverCtx.Config
			config.SetRoot(clientCtx.HomeDir)

			chainID, _ := cmd.Flags().GetString(flags.FlagChainID)
			if chainID == "" && clientCtx.ChainID != "" {
				chainID = clientCtx.ChainID
			}
			if chainID == "" {
				chainID = app.DefaultChainID
			}

			var mnemonic string
			recoverKey, _ := cmd.Flags().GetBool(genutilcli.FlagRecover)
			if recoverKey {
				inBuf := bufio.NewReader(cmd.InOrStdin())
				value, err := input.GetString("Enter your bip39 mnemonic", inBuf)
				if err != nil {
					return err
				}
				if !bip39.IsMnemonicValid(value) {
					return errors.New("invalid mnemonic")
				}
				mnemonic = value
			}

			initHeight, _ := cmd.Flags().GetInt64(flags.FlagInitHeight)
			if initHeight < 1 {
				initHeight = 1
			}

			nodeID, _, err := initializeNodeValidatorFilesFromMnemonic(config, mnemonic)
			if err != nil {
				return err
			}

			config.Moniker = args[0]
			genFile := config.GenesisFile()
			overwrite, _ := cmd.Flags().GetBool(genutilcli.FlagOverwrite)
			defaultDenom, _ := cmd.Flags().GetString(genutilcli.FlagDefaultBondDenom)
			if defaultDenom != "" && defaultDenom != app.DefaultBaseDenom {
				return fmt.Errorf("kudora init only supports %q as the genesis default denomination", app.DefaultBaseDenom)
			}

			if _, err := os.Stat(genFile); err == nil && !overwrite {
				return fmt.Errorf("genesis.json file already exists: %v", genFile)
			} else if err != nil && !os.IsNotExist(err) {
				return err
			}

			appGenState := kudoraApp.DefaultGenesis()
			appState, err := json.MarshalIndent(appGenState, "", " ")
			if err != nil {
				return errorsmod.Wrap(err, "failed to marshal kudora default genesis state")
			}

			appGenesis := &genutiltypes.AppGenesis{
				AppName:       version.AppName,
				AppVersion:    version.Version,
				ChainID:       chainID,
				AppState:      appState,
				InitialHeight: initHeight,
				Consensus: &genutiltypes.ConsensusGenesis{
					Validators: nil,
					Params:     cmttypes.DefaultConsensusParams(),
				},
			}

			consensusKeyAlgo, err := cmd.Flags().GetString(genutilcli.FlagConsensusKeyAlgo)
			if err != nil {
				return errorsmod.Wrap(err, "failed to get consensus key algo")
			}
			appGenesis.Consensus.Params.Validator.PubKeyTypes = []string{consensusKeyAlgo}

			if err := appGenesis.ValidateAndComplete(); err != nil {
				return errorsmod.Wrap(err, "failed to validate kudora genesis file")
			}
			if err := appGenesis.SaveAs(genFile); err != nil {
				return errorsmod.Wrap(err, "failed to export genesis file")
			}

			info := initPrintInfo{
				Moniker:    config.Moniker,
				ChainID:    chainID,
				NodeID:     nodeID,
				GenTxsDir:  filepath.Join(config.RootDir, "config", "gentx"),
				AppMessage: appState,
			}
			out, err := json.MarshalIndent(info, "", " ")
			if err != nil {
				return err
			}

			cfg.WriteConfigFile(filepath.Join(config.RootDir, "config", "config.toml"), config)

			otelFile := filepath.Join(clientCtx.HomeDir, "config", telemetry.OtelFileName)
			if err := os.WriteFile(otelFile, []byte{}, 0o600); err != nil {
				return errorsmod.Wrap(err, "failed to create otel.yaml file")
			}

			_, err = fmt.Fprintf(os.Stderr, "%s\n", out)
			return err
		},
	}

	cmd.Flags().String(flags.FlagHome, app.DefaultNodeHome, "node's home directory")
	cmd.Flags().BoolP(genutilcli.FlagOverwrite, "o", false, "overwrite the genesis.json file")
	cmd.Flags().Bool(genutilcli.FlagRecover, false, "provide seed phrase to recover existing key instead of creating")
	cmd.Flags().String(flags.FlagChainID, app.DefaultChainID, "genesis file chain-id")
	cmd.Flags().String(genutilcli.FlagDefaultBondDenom, app.DefaultBaseDenom, "genesis file default denomination")
	cmd.Flags().Int64(flags.FlagInitHeight, 1, "specify the initial block height at genesis")
	cmd.Flags().String(genutilcli.FlagConsensusKeyAlgo, ed25519.KeyType, "algorithm to use for the consensus key")

	return cmd
}
