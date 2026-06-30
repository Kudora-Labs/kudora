package types

import (
	codectypes "github.com/cosmos/cosmos-sdk/codec/types"
	sdk "github.com/cosmos/cosmos-sdk/types"
	"github.com/cosmos/cosmos-sdk/types/msgservice"
)

func RegisterInterfaces(registrar codectypes.InterfaceRegistry) {
	registrar.RegisterImplementations((*sdk.Msg)(nil),
		&MsgCommitIntegritySet{},
	)

	registrar.RegisterImplementations((*sdk.Msg)(nil),
		&MsgRegisterTenant{},
	)

	registrar.RegisterImplementations((*sdk.Msg)(nil),
		&MsgTransferTenantOwnership{},
		&MsgAcceptTenantOwnership{},
		&MsgCancelTenantOwnershipTransfer{},
	)

	registrar.RegisterImplementations((*sdk.Msg)(nil),
		&MsgUpdateParams{},
	)
	msgservice.RegisterMsgServiceDesc(registrar, &_Msg_serviceDesc)
}
