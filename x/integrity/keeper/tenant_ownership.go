package keeper

import (
	"context"

	errorsmod "cosmossdk.io/errors"

	"github.com/Kudora-Labs/kudora/x/integrity/types"
)

func (k msgServer) validatedAddress(address string, field string) (string, error) {
	normalized, err := types.NormalizeOwnerAddress(address, field)
	if err != nil {
		return "", err
	}
	if _, err := k.addressCodec.StringToBytes(normalized); err != nil {
		return "", errorsmod.Wrapf(err, "invalid %s address", field)
	}
	return normalized, nil
}

func (k msgServer) validatedCreator(creator string) (string, error) {
	return k.validatedAddress(creator, "creator")
}

func (k msgServer) tenantForUpdate(ctx context.Context, tenant string) (string, types.Tenant, error) {
	normalizedTenant, err := types.NormalizeTenant(tenant)
	if err != nil {
		return "", types.Tenant{}, err
	}

	tenantRecord, err := k.GetTenant(ctx, normalizedTenant)
	if err != nil {
		return "", types.Tenant{}, err
	}

	return normalizedTenant, tenantRecord, nil
}
