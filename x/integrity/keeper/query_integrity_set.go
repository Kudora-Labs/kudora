package keeper

import (
	"context"
	"errors"

	"github.com/Kudora-Labs/kudora/x/integrity/types"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

func (q queryServer) IntegritySet(ctx context.Context, req *types.QueryIntegritySetRequest) (*types.QueryIntegritySetResponse, error) {
	if req == nil {
		return nil, status.Error(codes.InvalidArgument, "invalid request")
	}

	tenant, err := types.NormalizeTenant(req.Tenant)
	if err != nil {
		return nil, status.Error(codes.InvalidArgument, err.Error())
	}
	integrityType, err := types.NormalizeIntegrityType(req.Type)
	if err != nil {
		return nil, status.Error(codes.InvalidArgument, err.Error())
	}
	period, err := types.NormalizePeriod(req.Period)
	if err != nil {
		return nil, status.Error(codes.InvalidArgument, err.Error())
	}

	integritySet, err := q.k.GetIntegritySet(ctx, tenant, integrityType, period)
	if err != nil {
		if errors.Is(err, types.ErrIntegritySetNotFound) {
			return nil, status.Error(codes.NotFound, err.Error())
		}
		return nil, status.Error(codes.Internal, err.Error())
	}

	records, err := q.k.ListIntegrityRecords(ctx, tenant, integrityType, period)
	if err != nil {
		return nil, status.Error(codes.Internal, err.Error())
	}

	return &types.QueryIntegritySetResponse{
		Set:     integritySet,
		Records: records,
	}, nil
}
