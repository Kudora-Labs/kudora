package keeper

import (
	"context"

	sdk "github.com/cosmos/cosmos-sdk/types"

	"github.com/Kudora-Labs/kudora/x/integrity/types"
)

func (k msgServer) TransferTenantOwnership(ctx context.Context, msg *types.MsgTransferTenantOwnership) (*types.MsgTransferTenantOwnershipResponse, error) {
	if err := msg.ValidateBasic(); err != nil {
		return nil, err
	}

	creator, err := k.validatedCreator(msg.Creator)
	if err != nil {
		return nil, err
	}
	newOwner, err := k.validatedAddress(msg.NewOwner, "new owner")
	if err != nil {
		return nil, err
	}

	tenant, tenantRecord, err := k.tenantForUpdate(ctx, msg.Tenant)
	if err != nil {
		return nil, err
	}
	if tenantRecord.Owner != creator {
		return nil, types.ErrUnauthorizedTenantOwner.Wrapf("tenant %s is owned by %s", tenant, tenantRecord.Owner)
	}
	if tenantRecord.Owner == newOwner {
		return nil, types.ErrTenantOwnershipUnchanged.Wrap("new owner must differ from the current owner")
	}

	tenantRecord.PendingOwner = newOwner
	if err := k.Tenants.Set(ctx, tenant, tenantRecord); err != nil {
		return nil, err
	}

	sdk.UnwrapSDKContext(ctx).EventManager().EmitEvent(
		sdk.NewEvent(
			types.EventTypeTenantOwnershipTransferStarted,
			sdk.NewAttribute(types.AttributeKeyTenant, tenant),
			sdk.NewAttribute(types.AttributeKeyOwner, creator),
			sdk.NewAttribute(types.AttributeKeyPendingOwner, newOwner),
		),
	)

	return &types.MsgTransferTenantOwnershipResponse{}, nil
}
