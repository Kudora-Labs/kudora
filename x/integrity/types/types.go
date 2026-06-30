package types

const (
	EventTypeTenantRegistered                = "tenant_registered"
	EventTypeTenantOwnershipTransferStarted  = "tenant_ownership_transfer_started"
	EventTypeTenantOwnershipTransferred      = "tenant_ownership_transferred"
	EventTypeTenantOwnershipTransferCanceled = "tenant_ownership_transfer_canceled"
	EventTypeIntegrityCommitted              = "integrity_set_committed"

	AttributeKeyTenant        = "tenant"
	AttributeKeyOwner         = "owner"
	AttributeKeyPendingOwner  = "pending_owner"
	AttributeKeyPreviousOwner = "previous_owner"
	AttributeKeyType          = "type"
	AttributeKeyPeriod        = "period"
	AttributeKeyRoot          = "root"
	AttributeKeyCreator       = "creator"
	AttributeKeyRecordCount   = "record_count"
)
