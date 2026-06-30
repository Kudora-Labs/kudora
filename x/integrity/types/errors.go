package types

// DONTCOVER

import (
	"cosmossdk.io/errors"
)

// x/integrity module sentinel errors
var (
	ErrInvalidSigner             = errors.Register(ModuleName, 1100, "expected gov account as only signer for proposal message")
	ErrInvalidTenant             = errors.Register(ModuleName, 1101, "invalid tenant")
	ErrInvalidType               = errors.Register(ModuleName, 1102, "invalid integrity type")
	ErrInvalidPeriod             = errors.Register(ModuleName, 1103, "invalid period")
	ErrInvalidRoot               = errors.Register(ModuleName, 1104, "invalid root")
	ErrInvalidRecord             = errors.Register(ModuleName, 1105, "invalid integrity record")
	ErrTenantAlreadyExists       = errors.Register(ModuleName, 1106, "tenant already exists")
	ErrTenantNotFound            = errors.Register(ModuleName, 1107, "tenant not found")
	ErrUnauthorizedTenantOwner   = errors.Register(ModuleName, 1108, "creator is not the tenant owner")
	ErrIntegritySetAlreadyExists = errors.Register(ModuleName, 1109, "integrity set already exists")
	ErrIntegritySetNotFound      = errors.Register(ModuleName, 1110, "integrity set not found")
	ErrIntegrityRecordNotFound   = errors.Register(ModuleName, 1111, "integrity record not found")
	ErrRootMismatch              = errors.Register(ModuleName, 1112, "submitted root does not match calculated root")
	ErrDuplicateTag              = errors.Register(ModuleName, 1113, "duplicate record tag")
	ErrEmptyRecords              = errors.Register(ModuleName, 1114, "records must not be empty")
	ErrTooManyRecords            = errors.Register(ModuleName, 1115, "too many records")
	ErrCiphertextTooLarge        = errors.Register(ModuleName, 1116, "ciphertext exceeds the configured limit")
	ErrTotalCiphertextTooLarge   = errors.Register(ModuleName, 1117, "total ciphertext exceeds the configured limit")
	ErrTenantTransferNotPending  = errors.Register(ModuleName, 1118, "tenant ownership transfer is not pending")
	ErrUnauthorizedPendingOwner  = errors.Register(ModuleName, 1119, "creator is not the pending tenant owner")
	ErrTenantOwnershipUnchanged  = errors.Register(ModuleName, 1120, "tenant ownership would remain unchanged")
)
