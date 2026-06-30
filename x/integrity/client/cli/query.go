package cli

import (
	"github.com/spf13/cobra"

	"github.com/cosmos/cosmos-sdk/client"
	"github.com/cosmos/cosmos-sdk/client/flags"

	"github.com/Kudora-Labs/kudora/x/integrity/types"
)

func GetQueryCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:                        types.ModuleName,
		Short:                      "Integrity query subcommands",
		DisableFlagParsing:         false,
		SuggestionsMinimumDistance: 2,
		RunE:                       client.ValidateCmd,
	}

	cmd.AddCommand(
		CmdQueryTenant(),
		CmdQuerySet(),
		CmdQueryRecord(),
	)

	return cmd
}

func CmdQueryTenant() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "tenant [tenant]",
		Short: "Query one registered tenant",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			clientCtx, err := client.GetClientQueryContext(cmd)
			if err != nil {
				return err
			}

			res, err := types.NewQueryClient(clientCtx).Tenant(cmd.Context(), &types.QueryTenantRequest{Tenant: args[0]})
			if err != nil {
				return err
			}

			return clientCtx.PrintProto(res)
		},
	}

	flags.AddQueryFlagsToCmd(cmd)
	return cmd
}

func CmdQuerySet() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "set [tenant] [type] [period]",
		Short: "Query one committed integrity set and all of its records",
		Args:  cobra.ExactArgs(3),
		RunE: func(cmd *cobra.Command, args []string) error {
			clientCtx, err := client.GetClientQueryContext(cmd)
			if err != nil {
				return err
			}

			res, err := types.NewQueryClient(clientCtx).IntegritySet(cmd.Context(), &types.QueryIntegritySetRequest{
				Tenant: args[0],
				Type:   args[1],
				Period: args[2],
			})
			if err != nil {
				return err
			}

			return clientCtx.PrintProto(res)
		},
	}

	flags.AddQueryFlagsToCmd(cmd)
	return cmd
}

func CmdQueryRecord() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "record [tenant] [type] [period] [tag]",
		Short: "Query one encrypted integrity record by tag",
		Args:  cobra.ExactArgs(4),
		RunE: func(cmd *cobra.Command, args []string) error {
			clientCtx, err := client.GetClientQueryContext(cmd)
			if err != nil {
				return err
			}

			res, err := types.NewQueryClient(clientCtx).IntegrityRecord(cmd.Context(), &types.QueryIntegrityRecordRequest{
				Tenant: args[0],
				Type:   args[1],
				Period: args[2],
				Tag:    args[3],
			})
			if err != nil {
				return err
			}

			return clientCtx.PrintProto(res)
		},
	}

	flags.AddQueryFlagsToCmd(cmd)
	return cmd
}
