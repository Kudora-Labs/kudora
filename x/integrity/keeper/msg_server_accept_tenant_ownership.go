package keeper

import (
	"context"

	sdk "github.com/cosmos/cosmos-sdk/types"

	"github.com/Kudora-Labs/kudora/x/integrity/types"
)

func (k msgServer) AcceptTenantOwnership(ctx context.Context, msg *types.MsgAcceptTenantOwnership) (*types.MsgAcceptTenantOwnershipResponse, error) {
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
	if tenantRecord.PendingOwner == "" {
		return nil, types.ErrTenantTransferNotPending.Wrapf("tenant %s has no pending owner", tenant)
	}
	if tenantRecord.PendingOwner != creator {
		return nil, types.ErrUnauthorizedPendingOwner.Wrapf("tenant %s pending owner is %s", tenant, tenantRecord.PendingOwner)
	}

	previousOwner := tenantRecord.Owner
	tenantRecord.Owner = creator
	tenantRecord.PendingOwner = ""
	if err := k.Tenants.Set(ctx, tenant, tenantRecord); err != nil {
		return nil, err
	}

	sdk.UnwrapSDKContext(ctx).EventManager().EmitEvent(
		sdk.NewEvent(
			types.EventTypeTenantOwnershipTransferred,
			sdk.NewAttribute(types.AttributeKeyTenant, tenant),
			sdk.NewAttribute(types.AttributeKeyPreviousOwner, previousOwner),
			sdk.NewAttribute(types.AttributeKeyOwner, creator),
		),
	)

	return &types.MsgAcceptTenantOwnershipResponse{}, nil
}
