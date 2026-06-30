package cli

import (
	"encoding/json"
	"os"

	"github.com/spf13/cobra"

	"github.com/cosmos/cosmos-sdk/client"
	"github.com/cosmos/cosmos-sdk/client/flags"
	clienttx "github.com/cosmos/cosmos-sdk/client/tx"

	"github.com/Kudora-Labs/kudora/x/integrity/types"
)

func GetTxCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:                        types.ModuleName,
		Short:                      "Integrity transaction subcommands",
		DisableFlagParsing:         false,
		SuggestionsMinimumDistance: 2,
		RunE:                       client.ValidateCmd,
	}

	cmd.AddCommand(
		CmdRegisterTenant(),
		CmdTransferTenantOwnership(),
		CmdAcceptTenantOwnership(),
		CmdCancelTenantOwnershipTransfer(),
		CmdCommitSet(),
	)

	return cmd
}

func CmdRegisterTenant() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "register-tenant [tenant]",
		Short: "Register a tenant namespace",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			clientCtx, err := client.GetClientTxContext(cmd)
			if err != nil {
				return err
			}

			msg := &types.MsgRegisterTenant{
				Creator: clientCtx.GetFromAddress().String(),
				Tenant:  args[0],
			}
			if err := msg.ValidateBasic(); err != nil {
				return err
			}

			return clienttx.GenerateOrBroadcastTxCLI(clientCtx, cmd.Flags(), msg)
		},
	}

	flags.AddTxFlagsToCmd(cmd)
	return cmd
}

func CmdCommitSet() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "commit-set [tenant] [type] [period] [root] [records-file]",
		Short: "Commit an encrypted integrity set",
		Args:  cobra.ExactArgs(5),
		RunE: func(cmd *cobra.Command, args []string) error {
			clientCtx, err := client.GetClientTxContext(cmd)
			if err != nil {
				return err
			}

			records, err := readIntegrityRecordsFile(args[4])
			if err != nil {
				return err
			}

			msg := &types.MsgCommitIntegritySet{
				Creator: clientCtx.GetFromAddress().String(),
				Tenant:  args[0],
				Type:    args[1],
				Period:  args[2],
				Root:    args[3],
				Records: records,
			}
			if err := msg.ValidateBasic(); err != nil {
				return err
			}

			return clienttx.GenerateOrBroadcastTxCLI(clientCtx, cmd.Flags(), msg)
		},
	}

	flags.AddTxFlagsToCmd(cmd)
	return cmd
}

func CmdTransferTenantOwnership() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "transfer-tenant-ownership [tenant] [new-owner]",
		Short: "Start a two-step tenant ownership transfer",
		Args:  cobra.ExactArgs(2),
		RunE: func(cmd *cobra.Command, args []string) error {
			clientCtx, err := client.GetClientTxContext(cmd)
			if err != nil {
				return err
			}

			msg := &types.MsgTransferTenantOwnership{
				Creator:  clientCtx.GetFromAddress().String(),
				Tenant:   args[0],
				NewOwner: args[1],
			}
			if err := msg.ValidateBasic(); err != nil {
				return err
			}

			return clienttx.GenerateOrBroadcastTxCLI(clientCtx, cmd.Flags(), msg)
		},
	}

	flags.AddTxFlagsToCmd(cmd)
	return cmd
}

func CmdAcceptTenantOwnership() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "accept-tenant-ownership [tenant]",
		Short: "Accept a pending tenant ownership transfer",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			clientCtx, err := client.GetClientTxContext(cmd)
			if err != nil {
				return err
			}

			msg := &types.MsgAcceptTenantOwnership{
				Creator: clientCtx.GetFromAddress().String(),
				Tenant:  args[0],
			}
			if err := msg.ValidateBasic(); err != nil {
				return err
			}

			return clienttx.GenerateOrBroadcastTxCLI(clientCtx, cmd.Flags(), msg)
		},
	}

	flags.AddTxFlagsToCmd(cmd)
	return cmd
}

func CmdCancelTenantOwnershipTransfer() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "cancel-tenant-ownership-transfer [tenant]",
		Short: "Cancel a pending tenant ownership transfer",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			clientCtx, err := client.GetClientTxContext(cmd)
			if err != nil {
				return err
			}

			msg := &types.MsgCancelTenantOwnershipTransfer{
				Creator: clientCtx.GetFromAddress().String(),
				Tenant:  args[0],
			}
			if err := msg.ValidateBasic(); err != nil {
				return err
			}

			return clienttx.GenerateOrBroadcastTxCLI(clientCtx, cmd.Flags(), msg)
		},
	}

	flags.AddTxFlagsToCmd(cmd)
	return cmd
}

func readIntegrityRecordsFile(path string) ([]types.IntegrityRecord, error) {
	payload, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var records []types.IntegrityRecord
	if err := json.Unmarshal(payload, &records); err == nil && len(records) > 0 {
		return records, nil
	}

	var wrapper struct {
		Records []types.IntegrityRecord `json:"records"`
	}
	if err := json.Unmarshal(payload, &wrapper); err != nil {
		return nil, err
	}

	return wrapper.Records, nil
}
