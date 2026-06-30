package keeper

import (
	"context"

	sdk "github.com/cosmos/cosmos-sdk/types"

	"github.com/Kudora-Labs/kudora/x/integrity/types"
)

func (k msgServer) CancelTenantOwnershipTransfer(ctx context.Context, msg *types.MsgCancelTenantOwnershipTransfer) (*types.MsgCancelTenantOwnershipTransferResponse, error) {
	if err := msg.ValidateBasic(); err != nil {
		return nil, err
	}

	creator, err := k.validatedCreator(msg.Creator)
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
	if tenantRecord.PendingOwner == "" {
		return nil, types.ErrTenantTransferNotPending.Wrapf("tenant %s has no pending owner", tenant)
	}

	pendingOwner := tenantRecord.PendingOwner
	tenantRecord.PendingOwner = ""
	if err := k.Tenants.Set(ctx, tenant, tenantRecord); err != nil {
		return nil, err
	}

	sdk.UnwrapSDKContext(ctx).EventManager().EmitEvent(
		sdk.NewEvent(
			types.EventTypeTenantOwnershipTransferCanceled,
			sdk.NewAttribute(types.AttributeKeyTenant, tenant),
			sdk.NewAttribute(types.AttributeKeyOwner, creator),
			sdk.NewAttribute(types.AttributeKeyPendingOwner, pendingOwner),
		),
	)

	return &types.MsgCancelTenantOwnershipTransferResponse{}, nil
}
