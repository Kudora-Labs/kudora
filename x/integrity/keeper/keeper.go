package keeper

import (
	"fmt"

	"cosmossdk.io/collections"
	"cosmossdk.io/core/address"
	corestore "cosmossdk.io/core/store"
	"github.com/cosmos/cosmos-sdk/codec"

	"github.com/Kudora-Labs/kudora/x/integrity/types"
)

type Keeper struct {
	storeService corestore.KVStoreService
	cdc          codec.Codec
	addressCodec address.Codec
	// Address capable of executing a MsgUpdateParams message.
	// Typically, this should be the x/gov module account.
	authority []byte

	Schema           collections.Schema
	Params           collections.Item[types.Params]
	Tenants          collections.Map[string, types.Tenant]
	IntegritySets    collections.Map[collections.Triple[string, string, string], types.IntegritySet]
	IntegrityRecords collections.Map[collections.Quad[string, string, string, string], types.IntegrityRecord]

	bankKeeper types.BankKeeper
}

func NewKeeper(
	storeService corestore.KVStoreService,
	cdc codec.Codec,
	addressCodec address.Codec,
	authority []byte,
	bankKeeper types.BankKeeper,
) Keeper {
	if _, err := addressCodec.BytesToString(authority); err != nil {
		panic(fmt.Sprintf("invalid authority address %s: %s", authority, err))
	}

	sb := collections.NewSchemaBuilder(storeService)

	k := Keeper{
		storeService: storeService,
		cdc:          cdc,
		addressCodec: addressCodec,
		authority:    authority,
		bankKeeper:   bankKeeper,
		Params:       collections.NewItem(sb, types.ParamsKey, "params", codec.CollValue[types.Params](cdc)),
		Tenants: collections.NewMap(
			sb,
			types.TenantKeyPrefix,
			"tenants",
			collections.StringKey,
			codec.CollValue[types.Tenant](cdc),
		),
		IntegritySets: collections.NewMap(
			sb,
			types.IntegritySetPrefix,
			"integrity_sets",
			collections.TripleKeyCodec(collections.StringKey, collections.StringKey, collections.StringKey),
			codec.CollValue[types.IntegritySet](cdc),
		),
		IntegrityRecords: collections.NewMap(
			sb,
			types.IntegrityRecordPrefix,
			"integrity_records",
			collections.QuadKeyCodec(collections.StringKey, collections.StringKey, collections.StringKey, collections.StringKey),
			codec.CollValue[types.IntegrityRecord](cdc),
		),
	}

	schema, err := sb.Build()
	if err != nil {
		panic(err)
	}
	k.Schema = schema

	return k
}

// GetAuthority returns the module's authority.
func (k Keeper) GetAuthority() []byte {
	return k.authority
}
