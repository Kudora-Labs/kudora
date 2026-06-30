package keeper_test

import (
	"context"
	"testing"

	"github.com/cosmos/cosmos-sdk/crypto/keys/secp256k1"
	sdk "github.com/cosmos/cosmos-sdk/types"
	"github.com/stretchr/testify/require"
	"google.golang.org/grpc/codes"
	grpcstatus "google.golang.org/grpc/status"

	"github.com/Kudora-Labs/kudora/testutil/integritymock"
	"github.com/Kudora-Labs/kudora/x/integrity/keeper"
	"github.com/Kudora-Labs/kudora/x/integrity/types"
)

func TestRegisterTenantAndDuplicateProtection(t *testing.T) {
	f := initFixture(t)
	msgServer := keeper.NewMsgServerImpl(f.keeper)
	creator := randomAddress()

	_, err := msgServer.RegisterTenant(f.ctx, &types.MsgRegisterTenant{
		Creator: creator,
		Tenant:  "orbitrum",
	})
	require.NoError(t, err)

	tenantResp, err := keeper.NewQueryServerImpl(f.keeper).Tenant(f.ctx, &types.QueryTenantRequest{Tenant: "orbitrum"})
	require.NoError(t, err)
	require.Equal(t, "orbitrum", tenantResp.Tenant.Tenant)
	require.Equal(t, creator, tenantResp.Tenant.Owner)
	require.Empty(t, tenantResp.Tenant.PendingOwner)

	_, err = msgServer.RegisterTenant(f.ctx, &types.MsgRegisterTenant{
		Creator: creator,
		Tenant:  "orbitrum",
	})
	require.ErrorIs(t, err, types.ErrTenantAlreadyExists)
}

func TestCommitIntegritySetLifecycle(t *testing.T) {
	f := initFixture(t)
	msgServer := keeper.NewMsgServerImpl(f.keeper)
	queryServer := keeper.NewQueryServerImpl(f.keeper)
	creator := randomAddress()
	tenant := "acme"
	integrityType := "acme.integrity.bundle.v1"
	period := "2026-06-25"

	_, err := msgServer.RegisterTenant(f.ctx, &types.MsgRegisterTenant{Creator: creator, Tenant: tenant})
	require.NoError(t, err)

	mockSet, err := integritymock.BuildMockSet(2, tenant, integrityType, period)
	require.NoError(t, err)

	_, err = msgServer.CommitIntegritySet(f.ctx, &types.MsgCommitIntegritySet{
		Creator: creator,
		Tenant:  tenant,
		Type:    integrityType,
		Period:  period,
		Root:    mockSet.Root,
		Records: mockSet.Records,
	})
	require.NoError(t, err)

	setResp, err := queryServer.IntegritySet(f.ctx, &types.QueryIntegritySetRequest{
		Tenant: tenant,
		Type:   integrityType,
		Period: period,
	})
	require.NoError(t, err)
	require.Equal(t, mockSet.Root, setResp.Set.Root)
	require.Len(t, setResp.Records, 2)
	require.Equal(t, mockSet.SortedTags, []string{setResp.Records[0].Tag, setResp.Records[1].Tag})

	recordResp, err := queryServer.IntegrityRecord(f.ctx, &types.QueryIntegrityRecordRequest{
		Tenant: tenant,
		Type:   integrityType,
		Period: period,
		Tag:    mockSet.SortedTags[0],
	})
	require.NoError(t, err)
	require.Equal(t, mockSet.SortedTags[0], recordResp.Record.Tag)
	require.Equal(t, mockSet.Root, recordResp.Set.Root)
}

func TestTenantOwnershipTransferLifecycle(t *testing.T) {
	f := initFixture(t)
	msgServer := keeper.NewMsgServerImpl(f.keeper)
	queryServer := keeper.NewQueryServerImpl(f.keeper)
	ownerA := randomAddress()
	ownerB := randomAddress()
	randomUser := randomAddress()
	tenant := "orbitrum"
	integrityType := "orbitrum.scoring.expert_daily_bundle.v1"

	_, err := msgServer.RegisterTenant(f.ctx, &types.MsgRegisterTenant{Creator: ownerA, Tenant: tenant})
	require.NoError(t, err)

	registeredTenant, err := queryServer.Tenant(f.ctx, &types.QueryTenantRequest{Tenant: tenant})
	require.NoError(t, err)
	require.Equal(t, ownerA, registeredTenant.Tenant.Owner)
	require.Empty(t, registeredTenant.Tenant.PendingOwner)

	ownerASet := commitSetOrFail(t, f.ctx, msgServer, ownerA, tenant, integrityType, "2026-06-25")
	require.NotEmpty(t, ownerASet.Root)

	_, err = msgServer.TransferTenantOwnership(f.ctx, &types.MsgTransferTenantOwnership{
		Creator:  randomUser,
		Tenant:   tenant,
		NewOwner: ownerB,
	})
	require.ErrorIs(t, err, types.ErrUnauthorizedTenantOwner)

	_, err = msgServer.TransferTenantOwnership(f.ctx, &types.MsgTransferTenantOwnership{
		Creator:  ownerA,
		Tenant:   tenant,
		NewOwner: ownerB,
	})
	require.NoError(t, err)

	pendingTenant, err := queryServer.Tenant(f.ctx, &types.QueryTenantRequest{Tenant: tenant})
	require.NoError(t, err)
	require.Equal(t, ownerA, pendingTenant.Tenant.Owner)
	require.Equal(t, ownerB, pendingTenant.Tenant.PendingOwner)

	_, err = msgServer.CommitIntegritySet(f.ctx, &types.MsgCommitIntegritySet{
		Creator: ownerB,
		Tenant:  tenant,
		Type:    integrityType,
		Period:  "2026-06-26",
		Root:    ownerASet.Root,
		Records: ownerASet.Records,
	})
	require.ErrorIs(t, err, types.ErrUnauthorizedTenantOwner)

	preAcceptSet := commitSetOrFail(t, f.ctx, msgServer, ownerA, tenant, integrityType, "2026-06-27")
	require.NotEmpty(t, preAcceptSet.Root)

	_, err = msgServer.AcceptTenantOwnership(f.ctx, &types.MsgAcceptTenantOwnership{
		Creator: randomUser,
		Tenant:  tenant,
	})
	require.ErrorIs(t, err, types.ErrUnauthorizedPendingOwner)

	_, err = msgServer.AcceptTenantOwnership(f.ctx, &types.MsgAcceptTenantOwnership{
		Creator: ownerB,
		Tenant:  tenant,
	})
	require.NoError(t, err)

	transferredTenant, err := queryServer.Tenant(f.ctx, &types.QueryTenantRequest{Tenant: tenant})
	require.NoError(t, err)
	require.Equal(t, ownerB, transferredTenant.Tenant.Owner)
	require.Empty(t, transferredTenant.Tenant.PendingOwner)

	_, err = msgServer.CommitIntegritySet(f.ctx, &types.MsgCommitIntegritySet{
		Creator: ownerA,
		Tenant:  tenant,
		Type:    integrityType,
		Period:  "2026-06-28",
		Root:    preAcceptSet.Root,
		Records: preAcceptSet.Records,
	})
	require.ErrorIs(t, err, types.ErrUnauthorizedTenantOwner)

	postAcceptSet := commitSetOrFail(t, f.ctx, msgServer, ownerB, tenant, integrityType, "2026-06-29")
	require.NotEmpty(t, postAcceptSet.Root)
}

func TestTenantOwnershipTransferCancellationAndValidation(t *testing.T) {
	f := initFixture(t)
	msgServer := keeper.NewMsgServerImpl(f.keeper)
	queryServer := keeper.NewQueryServerImpl(f.keeper)
	ownerA := randomAddress()
	ownerB := randomAddress()
	tenant := "acme"

	_, err := msgServer.RegisterTenant(f.ctx, &types.MsgRegisterTenant{Creator: ownerA, Tenant: tenant})
	require.NoError(t, err)

	_, err = msgServer.TransferTenantOwnership(f.ctx, &types.MsgTransferTenantOwnership{
		Creator:  ownerA,
		Tenant:   tenant,
		NewOwner: ownerA,
	})
	require.ErrorIs(t, err, types.ErrTenantOwnershipUnchanged)

	_, err = msgServer.TransferTenantOwnership(f.ctx, &types.MsgTransferTenantOwnership{
		Creator:  ownerA,
		Tenant:   tenant,
		NewOwner: "invalid",
	})
	require.Error(t, err)
	require.Contains(t, err.Error(), "invalid new owner address")

	_, err = msgServer.TransferTenantOwnership(f.ctx, &types.MsgTransferTenantOwnership{
		Creator:  ownerA,
		Tenant:   tenant,
		NewOwner: ownerB,
	})
	require.NoError(t, err)

	_, err = msgServer.CancelTenantOwnershipTransfer(f.ctx, &types.MsgCancelTenantOwnershipTransfer{
		Creator: ownerB,
		Tenant:  tenant,
	})
	require.ErrorIs(t, err, types.ErrUnauthorizedTenantOwner)

	_, err = msgServer.CancelTenantOwnershipTransfer(f.ctx, &types.MsgCancelTenantOwnershipTransfer{
		Creator: ownerA,
		Tenant:  tenant,
	})
	require.NoError(t, err)

	tenantResp, err := queryServer.Tenant(f.ctx, &types.QueryTenantRequest{Tenant: tenant})
	require.NoError(t, err)
	require.Equal(t, ownerA, tenantResp.Tenant.Owner)
	require.Empty(t, tenantResp.Tenant.PendingOwner)

	_, err = msgServer.AcceptTenantOwnership(f.ctx, &types.MsgAcceptTenantOwnership{
		Creator: ownerB,
		Tenant:  tenant,
	})
	require.ErrorIs(t, err, types.ErrTenantTransferNotPending)
}

func TestCommitIntegritySetRejectsUnauthorizedDuplicateAndBadInputs(t *testing.T) {
	f := initFixture(t)
	msgServer := keeper.NewMsgServerImpl(f.keeper)
	owner := randomAddress()
	other := randomAddress()
	tenant := "globex"
	integrityType := "globex.dataset.v1"
	period := "2026-06-25"
	var err error

	_, err = msgServer.RegisterTenant(f.ctx, &types.MsgRegisterTenant{Creator: owner, Tenant: tenant})
	require.NoError(t, err)

	mockSet, err := integritymock.BuildMockSet(2, tenant, integrityType, period)
	require.NoError(t, err)

	_, err = msgServer.CommitIntegritySet(f.ctx, &types.MsgCommitIntegritySet{
		Creator: other,
		Tenant:  tenant,
		Type:    integrityType,
		Period:  period,
		Root:    mockSet.Root,
		Records: mockSet.Records,
	})
	require.ErrorIs(t, err, types.ErrUnauthorizedTenantOwner)

	_, err = msgServer.CommitIntegritySet(f.ctx, &types.MsgCommitIntegritySet{
		Creator: owner,
		Tenant:  tenant,
		Type:    integrityType,
		Period:  period,
		Root:    "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		Records: mockSet.Records,
	})
	require.ErrorIs(t, err, types.ErrRootMismatch)

	_, err = msgServer.CommitIntegritySet(f.ctx, &types.MsgCommitIntegritySet{
		Creator: owner,
		Tenant:  tenant,
		Type:    integrityType,
		Period:  period,
		Root:    mockSet.Root,
		Records: mockSet.Records,
	})
	require.NoError(t, err)

	_, err = msgServer.CommitIntegritySet(f.ctx, &types.MsgCommitIntegritySet{
		Creator: owner,
		Tenant:  tenant,
		Type:    integrityType,
		Period:  period,
		Root:    mockSet.Root,
		Records: mockSet.Records,
	})
	require.ErrorIs(t, err, types.ErrIntegritySetAlreadyExists)

	_, err = msgServer.CommitIntegritySet(f.ctx, &types.MsgCommitIntegritySet{
		Creator: owner,
		Tenant:  tenant,
		Type:    "globex.dataset.v2",
		Period:  period,
		Root:    mockSet.Root,
		Records: []types.IntegrityRecord{
			mockSet.SortedRecords[0],
			mockSet.SortedRecords[0],
		},
	})
	require.ErrorIs(t, err, types.ErrDuplicateTag)

	_, err = msgServer.CommitIntegritySet(f.ctx, &types.MsgCommitIntegritySet{
		Creator: owner,
		Tenant:  tenant,
		Type:    "globex.dataset.v3",
		Period:  period,
		Root:    mockSet.Root,
		Records: []types.IntegrityRecord{},
	})
	require.ErrorIs(t, err, types.ErrEmptyRecords)

	_, err = msgServer.CommitIntegritySet(f.ctx, &types.MsgCommitIntegritySet{
		Creator: owner,
		Tenant:  tenant,
		Type:    "globex.dataset.v4",
		Period:  period,
		Root:    mockSet.Root,
		Records: []types.IntegrityRecord{
			{
				Tag:        "0x1234",
				Nonce:      "0x0102",
				Ciphertext: "0x0304",
			},
		},
	})
	require.ErrorIs(t, err, types.ErrInvalidRecord)
}

func TestQueryIntegrityNotFound(t *testing.T) {
	f := initFixture(t)
	queryServer := keeper.NewQueryServerImpl(f.keeper)

	_, err := queryServer.Tenant(f.ctx, &types.QueryTenantRequest{Tenant: "missing"})
	require.Equal(t, codes.NotFound, grpcstatus.Code(err))

	_, err = queryServer.IntegritySet(f.ctx, &types.QueryIntegritySetRequest{
		Tenant: "missing",
		Type:   "missing.dataset.v1",
		Period: "2026-06-25",
	})
	require.Equal(t, codes.NotFound, grpcstatus.Code(err))

	_, err = queryServer.IntegrityRecord(f.ctx, &types.QueryIntegrityRecordRequest{
		Tenant: "missing",
		Type:   "missing.dataset.v1",
		Period: "2026-06-25",
		Tag:    "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
	})
	require.Equal(t, codes.NotFound, grpcstatus.Code(err))
}

func TestOrbitrumLikeEncryptedRoundTrip(t *testing.T) {
	f := initFixture(t)
	msgServer := keeper.NewMsgServerImpl(f.keeper)
	queryServer := keeper.NewQueryServerImpl(f.keeper)
	creator := randomAddress()
	mockSet, err := integritymock.BuildMockSet(1, "orbitrum", "orbitrum.scoring.expert_daily_bundle.v1", "2026-06-25")
	require.NoError(t, err)

	_, err = msgServer.RegisterTenant(f.ctx, &types.MsgRegisterTenant{
		Creator: creator,
		Tenant:  mockSet.Tenant,
	})
	require.NoError(t, err)

	_, err = msgServer.CommitIntegritySet(f.ctx, &types.MsgCommitIntegritySet{
		Creator: creator,
		Tenant:  mockSet.Tenant,
		Type:    mockSet.Type,
		Period:  mockSet.Period,
		Root:    mockSet.Root,
		Records: mockSet.Records,
	})
	require.NoError(t, err)

	recordResp, err := queryServer.IntegrityRecord(f.ctx, &types.QueryIntegrityRecordRequest{
		Tenant: mockSet.Tenant,
		Type:   mockSet.Type,
		Period: mockSet.Period,
		Tag:    mockSet.SortedTags[0],
	})
	require.NoError(t, err)
	require.Equal(t, mockSet.SortedRecords[0], recordResp.Record)

	decrypted, err := integritymock.DecryptRecord(mockSet.Tenant, mockSet.Type, mockSet.Period, recordResp.Record)
	require.NoError(t, err)
	require.Equal(t, mockSet.Plaintexts[0], decrypted)
}

func randomAddress() string {
	privKey := secp256k1.GenPrivKey()
	return sdk.AccAddress(privKey.PubKey().Address()).String()
}

func commitSetOrFail(t *testing.T, ctx context.Context, msgServer types.MsgServer, creator, tenant, integrityType, period string) integritymock.MockSet {
	t.Helper()

	mockSet, err := integritymock.BuildMockSet(2, tenant, integrityType, period)
	require.NoError(t, err)

	_, err = msgServer.CommitIntegritySet(ctx, &types.MsgCommitIntegritySet{
		Creator: creator,
		Tenant:  tenant,
		Type:    integrityType,
		Period:  period,
		Root:    mockSet.Root,
		Records: mockSet.Records,
	})
	require.NoError(t, err)

	return mockSet
}
