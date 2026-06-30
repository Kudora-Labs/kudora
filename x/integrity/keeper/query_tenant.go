package keeper

import (
	"context"
	"errors"

	"github.com/Kudora-Labs/kudora/x/integrity/types"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

func (q queryServer) Tenant(ctx context.Context, req *types.QueryTenantRequest) (*types.QueryTenantResponse, error) {
	if req == nil {
		return nil, status.Error(codes.InvalidArgument, "invalid request")
	}

	tenant, err := types.NormalizeTenant(req.Tenant)
	if err != nil {
		return nil, status.Error(codes.InvalidArgument, err.Error())
	}

	tenantData, err := q.k.GetTenant(ctx, tenant)
	if err != nil {
		if errors.Is(err, types.ErrTenantNotFound) {
			return nil, status.Error(codes.NotFound, err.Error())
		}
		return nil, status.Error(codes.Internal, err.Error())
	}

	return &types.QueryTenantResponse{Tenant: tenantData}, nil
}
