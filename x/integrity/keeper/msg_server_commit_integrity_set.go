package keeper

import (
	"context"
	"strconv"
	"time"

	errorsmod "cosmossdk.io/errors"
	sdk "github.com/cosmos/cosmos-sdk/types"

	"cosmossdk.io/collections"

	"github.com/Kudora-Labs/kudora/x/integrity/types"
)

func (k msgServer) CommitIntegritySet(ctx context.Context, msg *types.MsgCommitIntegritySet) (*types.MsgCommitIntegritySetResponse, error) {
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
	integrityType, err := types.NormalizeIntegrityType(msg.Type)
	if err != nil {
		return nil, err
	}
	period, err := types.NormalizePeriod(msg.Period)
	if err != nil {
		return nil, err
	}
	submittedRoot, err := types.NormalizeRoot(msg.Root)
	if err != nil {
		return nil, err
	}

	tenantRecord, err := k.GetTenant(ctx, tenant)
	if err != nil {
		return nil, err
	}
	if tenantRecord.Owner != creator {
		return nil, types.ErrUnauthorizedTenantOwner.Wrapf("tenant %s is owned by %s", tenant, tenantRecord.Owner)
	}

	setExists, err := k.HasIntegritySet(ctx, tenant, integrityType, period)
	if err != nil {
		return nil, err
	}
	if setExists {
		return nil, types.ErrIntegritySetAlreadyExists.Wrapf("set %s/%s/%s already exists", tenant, integrityType, period)
	}

	calculatedRoot, records, err := types.CalculateMerkleRoot(msg.Records)
	if err != nil {
		return nil, err
	}
	if calculatedRoot != submittedRoot {
		return nil, types.ErrRootMismatch.Wrapf("submitted root %s does not match calculated root %s", submittedRoot, calculatedRoot)
	}

	sdkCtx := sdk.UnwrapSDKContext(ctx)
	integritySet := types.IntegritySet{
		Tenant:      tenant,
		Type:        integrityType,
		Period:      period,
		Root:        calculatedRoot,
		Creator:     creator,
		BlockHeight: uint64(sdkCtx.BlockHeight()),
		BlockTime:   sdkCtx.BlockTime().UTC().Format(time.RFC3339Nano),
		RecordCount: uint64(len(records)),
	}
	if err := k.IntegritySets.Set(ctx, collections.Join3(tenant, integrityType, period), integritySet); err != nil {
		return nil, err
	}

	for _, record := range records {
		if err := k.IntegrityRecords.Set(ctx, collections.Join4(tenant, integrityType, period, record.Tag), record); err != nil {
			return nil, err
		}
	}

	sdkCtx.EventManager().EmitEvent(
		sdk.NewEvent(
			types.EventTypeIntegrityCommitted,
			sdk.NewAttribute(types.AttributeKeyTenant, tenant),
			sdk.NewAttribute(types.AttributeKeyType, integrityType),
			sdk.NewAttribute(types.AttributeKeyPeriod, period),
			sdk.NewAttribute(types.AttributeKeyRoot, calculatedRoot),
			sdk.NewAttribute(types.AttributeKeyCreator, creator),
			sdk.NewAttribute(types.AttributeKeyRecordCount, strconv.Itoa(len(records))),
		),
	)

	return &types.MsgCommitIntegritySetResponse{}, nil
}
