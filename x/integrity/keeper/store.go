package keeper

import (
	"context"
	"errors"

	"cosmossdk.io/collections"

	"github.com/Kudora-Labs/kudora/x/integrity/types"
)

func (k Keeper) GetTenant(ctx context.Context, tenant string) (types.Tenant, error) {
	tenantData, err := k.Tenants.Get(ctx, tenant)
	if err != nil {
		if errors.Is(err, collections.ErrNotFound) {
			return types.Tenant{}, types.ErrTenantNotFound.Wrapf("tenant %s is not registered", tenant)
		}
		return types.Tenant{}, err
	}

	return tenantData, nil
}

func (k Keeper) HasTenant(ctx context.Context, tenant string) (bool, error) {
	return k.Tenants.Has(ctx, tenant)
}

func (k Keeper) GetIntegritySet(ctx context.Context, tenant, integrityType, period string) (types.IntegritySet, error) {
	set, err := k.IntegritySets.Get(ctx, collections.Join3(tenant, integrityType, period))
	if err != nil {
		if errors.Is(err, collections.ErrNotFound) {
			return types.IntegritySet{}, types.ErrIntegritySetNotFound.Wrapf("set %s/%s/%s was not found", tenant, integrityType, period)
		}
		return types.IntegritySet{}, err
	}

	return set, nil
}

func (k Keeper) HasIntegritySet(ctx context.Context, tenant, integrityType, period string) (bool, error) {
	return k.IntegritySets.Has(ctx, collections.Join3(tenant, integrityType, period))
}

func (k Keeper) GetIntegrityRecord(ctx context.Context, tenant, integrityType, period, tag string) (types.IntegrityRecord, error) {
	record, err := k.IntegrityRecords.Get(ctx, collections.Join4(tenant, integrityType, period, tag))
	if err != nil {
		if errors.Is(err, collections.ErrNotFound) {
			return types.IntegrityRecord{}, types.ErrIntegrityRecordNotFound.Wrapf("record %s was not found", tag)
		}
		return types.IntegrityRecord{}, err
	}

	return record, nil
}

func (k Keeper) ListIntegrityRecords(ctx context.Context, tenant, integrityType, period string) ([]types.IntegrityRecord, error) {
	records := make([]types.IntegrityRecord, 0)
	err := k.IntegrityRecords.Walk(
		ctx,
		collections.NewSuperPrefixedQuadRange3[string, string, string, string](tenant, integrityType, period),
		func(_ collections.Quad[string, string, string, string], value types.IntegrityRecord) (bool, error) {
			records = append(records, value)
			return false, nil
		},
	)
	if err != nil {
		return nil, err
	}

	return records, nil
}
