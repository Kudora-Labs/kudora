package types

// DefaultGenesis returns the default genesis state
func DefaultGenesis() *GenesisState {
	return &GenesisState{
		Params: DefaultParams(),
	}
}

// Validate performs basic genesis state validation returning an error upon any
// failure.
func (gs GenesisState) Validate() error {
	if err := gs.Params.Validate(); err != nil {
		return err
	}

	tenants := make(map[string]struct{}, len(gs.Tenants))
	for _, tenant := range gs.Tenants {
		normalizedTenant, err := NormalizeTenant(tenant.Tenant)
		if err != nil {
			return err
		}
		if _, exists := tenants[normalizedTenant]; exists {
			return ErrTenantAlreadyExists
		}
		tenants[normalizedTenant] = struct{}{}
		if _, err := NormalizeCreator(tenant.Owner); err != nil {
			return err
		}
		if tenant.PendingOwner != "" {
			pendingOwner, err := NormalizeOwnerAddress(tenant.PendingOwner, "pending owner")
			if err != nil {
				return err
			}
			if pendingOwner == tenant.Owner {
				return ErrTenantOwnershipUnchanged.Wrapf("tenant %s pending owner matches current owner", normalizedTenant)
			}
		}
	}

	setKeys := make(map[string]struct{}, len(gs.IntegritySetBundles))
	for _, bundle := range gs.IntegritySetBundles {
		set := bundle.Set
		tenant, err := NormalizeTenant(set.Tenant)
		if err != nil {
			return err
		}
		if _, ok := tenants[tenant]; !ok {
			return ErrTenantNotFound
		}
		setType, err := NormalizeIntegrityType(set.Type)
		if err != nil {
			return err
		}
		period, err := NormalizePeriod(set.Period)
		if err != nil {
			return err
		}
		root, err := NormalizeRoot(set.Root)
		if err != nil {
			return err
		}
		if _, err := NormalizeCreator(set.Creator); err != nil {
			return err
		}
		records, _, err := PrepareIntegrityRecords(bundle.Records)
		if err != nil {
			return err
		}
		if set.RecordCount != uint64(len(records)) {
			return ErrInvalidRecord.Wrap("record count does not match bundle length")
		}
		calculatedRoot := CalculateMerkleRootFromPreparedRecords(records)
		if calculatedRoot != root {
			return ErrRootMismatch
		}

		compositeKey := tenant + "|" + setType + "|" + period
		if _, exists := setKeys[compositeKey]; exists {
			return ErrIntegritySetAlreadyExists
		}
		setKeys[compositeKey] = struct{}{}
	}

	return nil
}
