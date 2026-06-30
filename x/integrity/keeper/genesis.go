package keeper

import (
	"context"

	"cosmossdk.io/collections"

	"github.com/Kudora-Labs/kudora/x/integrity/types"
)

// InitGenesis initializes the module's state from a provided genesis state.
func (k Keeper) InitGenesis(ctx context.Context, genState types.GenesisState) error {
	if err := genState.Validate(); err != nil {
		return err
	}
	if err := k.Params.Set(ctx, genState.Params); err != nil {
		return err
	}

	for _, tenant := range genState.Tenants {
		if err := k.Tenants.Set(ctx, tenant.Tenant, tenant); err != nil {
			return err
		}
	}

	for _, bundle := range genState.IntegritySetBundles {
		set := bundle.Set
		if err := k.IntegritySets.Set(ctx, collections.Join3(set.Tenant, set.Type, set.Period), set); err != nil {
			return err
		}
		for _, record := range bundle.Records {
			if err := k.IntegrityRecords.Set(ctx, collections.Join4(set.Tenant, set.Type, set.Period, record.Tag), record); err != nil {
				return err
			}
		}
	}

	return nil
}

// ExportGenesis returns the module's exported genesis.
func (k Keeper) ExportGenesis(ctx context.Context) (*types.GenesisState, error) {
	var err error

	genesis := types.DefaultGenesis()
	genesis.Params, err = k.Params.Get(ctx)
	if err != nil {
		return nil, err
	}

	genesis.Tenants = make([]types.Tenant, 0)
	if err := k.Tenants.Walk(ctx, nil, func(_ string, tenant types.Tenant) (bool, error) {
		genesis.Tenants = append(genesis.Tenants, tenant)
		return false, nil
	}); err != nil {
		return nil, err
	}

	genesis.IntegritySetBundles = make([]types.IntegritySetBundle, 0)
	if err := k.IntegritySets.Walk(
		ctx,
		nil,
		func(_ collections.Triple[string, string, string], integritySet types.IntegritySet) (bool, error) {
			records, err := k.ListIntegrityRecords(ctx, integritySet.Tenant, integritySet.Type, integritySet.Period)
			if err != nil {
				return true, err
			}
			genesis.IntegritySetBundles = append(genesis.IntegritySetBundles, types.IntegritySetBundle{
				Set:     integritySet,
				Records: records,
			})
			return false, nil
		},
	); err != nil {
		return nil, err
	}

	return genesis, nil
}
