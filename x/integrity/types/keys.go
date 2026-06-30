package types

import "cosmossdk.io/collections"

const (
	// ModuleName defines the module name
	ModuleName = "integrity"

	// StoreKey defines the primary module store key
	StoreKey = ModuleName

	// GovModuleName duplicates the gov module's name to avoid a dependency with x/gov.
	// It should be synced with the gov module's name if it is ever changed.
	// See: https://github.com/cosmos/cosmos-sdk/blob/v0.52.0-beta.2/x/gov/types/keys.go#L9
	GovModuleName           = "gov"
	MaxTenantLength         = 64
	MaxTypeLength           = 128
	MaxPeriodLength         = 64
	MaxRecordsPerSet        = 1024
	MaxNonceBytes           = 64
	MaxCiphertextBytes      = 32 * 1024
	MaxTotalCiphertextBytes = 4 * 1024 * 1024
)

// ParamsKey is the prefix to retrieve all Params
var (
	ParamsKey             = collections.NewPrefix(0)
	TenantKeyPrefix       = collections.NewPrefix(1)
	IntegritySetPrefix    = collections.NewPrefix(2)
	IntegrityRecordPrefix = collections.NewPrefix(3)
)
