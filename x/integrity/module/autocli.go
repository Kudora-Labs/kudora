package integrity

import (
	autocliv1 "cosmossdk.io/api/cosmos/autocli/v1"

	"github.com/Kudora-Labs/kudora/x/integrity/types"
)

// AutoCLIOptions implements the autocli.HasAutoCLIConfig interface.
func (am AppModule) AutoCLIOptions() *autocliv1.ModuleOptions {
	return &autocliv1.ModuleOptions{
		Query: &autocliv1.ServiceCommandDescriptor{
			Service: types.Query_serviceDesc.ServiceName,
			RpcCommandOptions: []*autocliv1.RpcCommandOptions{
				{
					RpcMethod: "Params",
					Use:       "params",
					Short:     "Shows the parameters of the module",
				},
				{
					RpcMethod:      "Tenant",
					Use:            "tenant [tenant]",
					Short:          "Query tenant",
					PositionalArgs: []*autocliv1.PositionalArgDescriptor{{ProtoField: "tenant"}},
				},
				{
					RpcMethod:      "IntegritySet",
					Use:            "set [tenant] [type] [period]",
					Short:          "Query an integrity set",
					PositionalArgs: []*autocliv1.PositionalArgDescriptor{{ProtoField: "tenant"}, {ProtoField: "type"}, {ProtoField: "period"}},
				},
				{
					RpcMethod:      "IntegrityRecord",
					Use:            "record [tenant] [type] [period] [tag]",
					Short:          "Query an integrity record",
					PositionalArgs: []*autocliv1.PositionalArgDescriptor{{ProtoField: "tenant"}, {ProtoField: "type"}, {ProtoField: "period"}, {ProtoField: "tag"}},
				},
			},
		},
		Tx: &autocliv1.ServiceCommandDescriptor{
			Service:              types.Msg_serviceDesc.ServiceName,
			EnhanceCustomCommand: true, // only required if you want to use the custom command
			RpcCommandOptions: []*autocliv1.RpcCommandOptions{
				{
					RpcMethod: "UpdateParams",
					Skip:      true, // skipped because authority gated
				},
				{
					RpcMethod:      "RegisterTenant",
					Use:            "register-tenant [tenant]",
					Short:          "Register a tenant namespace",
					PositionalArgs: []*autocliv1.PositionalArgDescriptor{{ProtoField: "tenant"}},
				},
				{
					RpcMethod:      "TransferTenantOwnership",
					Use:            "transfer-tenant-ownership [tenant] [new-owner]",
					Short:          "Start a two-step tenant ownership transfer",
					PositionalArgs: []*autocliv1.PositionalArgDescriptor{{ProtoField: "tenant"}, {ProtoField: "new_owner"}},
				},
				{
					RpcMethod:      "AcceptTenantOwnership",
					Use:            "accept-tenant-ownership [tenant]",
					Short:          "Accept a pending tenant ownership transfer",
					PositionalArgs: []*autocliv1.PositionalArgDescriptor{{ProtoField: "tenant"}},
				},
				{
					RpcMethod:      "CancelTenantOwnershipTransfer",
					Use:            "cancel-tenant-ownership-transfer [tenant]",
					Short:          "Cancel a pending tenant ownership transfer",
					PositionalArgs: []*autocliv1.PositionalArgDescriptor{{ProtoField: "tenant"}},
				},
				{
					RpcMethod:      "CommitIntegritySet",
					Use:            "commit-set [tenant] [type] [period] [root]",
					Short:          "Commit an encrypted integrity set",
					PositionalArgs: []*autocliv1.PositionalArgDescriptor{{ProtoField: "tenant"}, {ProtoField: "type"}, {ProtoField: "period"}, {ProtoField: "root"}},
				},
			},
		},
	}
}
