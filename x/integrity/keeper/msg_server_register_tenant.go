package keeper

import (
	"context"
	"time"

	errorsmod "cosmossdk.io/errors"
	sdk "github.com/cosmos/cosmos-sdk/types"

	"github.com/Kudora-Labs/kudora/x/integrity/types"
)

func (k msgServer) RegisterTenant(ctx context.Context, msg *types.MsgRegisterTenant) (*types.MsgRegisterTenantResponse, error) {
	if err := msg.ValidateBasic(); err != nil {
		return nil, err
	}
	creator, err := types.NormalizeCreator(msg.Creator)
	if err != nil {
		return nil, err
	}
	if _, err := k.addressCodec.StringToBytes(creator); err != nil {
		return nil, errorsmod.Wrap(err, "invalid authority address")
	}

	tenant, err := types.NormalizeTenant(msg.Tenant)
	if err != nil {
		return nil, err
	}

	exists, err := k.HasTenant(ctx, tenant)
	if err != nil {
		return nil, err
	}
	if exists {
		return nil, types.ErrTenantAlreadyExists.Wrapf("tenant %s is already registered", tenant)
	}

	sdkCtx := sdk.UnwrapSDKContext(ctx)
	tenantRecord := types.Tenant{
		Tenant:        tenant,
		Owner:         creator,
		CreatedHeight: uint64(sdkCtx.BlockHeight()),
		CreatedTime:   sdkCtx.BlockTime().UTC().Format(time.RFC3339Nano),
	}
	if err := k.Tenants.Set(ctx, tenant, tenantRecord); err != nil {
		return nil, err
	}

	sdkCtx.EventManager().EmitEvent(
		sdk.NewEvent(
			types.EventTypeTenantRegistered,
			sdk.NewAttribute(types.AttributeKeyTenant, tenant),
			sdk.NewAttribute(types.AttributeKeyOwner, creator),
		),
	)

	return &types.MsgRegisterTenantResponse{}, nil
}
