package keeper

import (
	"context"
	"errors"

	"github.com/Kudora-Labs/kudora/x/integrity/types"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

func (q queryServer) IntegrityRecord(ctx context.Context, req *types.QueryIntegrityRecordRequest) (*types.QueryIntegrityRecordResponse, error) {
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
	tag, err := types.NormalizeTag(req.Tag)
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

	record, err := q.k.GetIntegrityRecord(ctx, tenant, integrityType, period, tag)
	if err != nil {
		if errors.Is(err, types.ErrIntegrityRecordNotFound) {
			return nil, status.Error(codes.NotFound, err.Error())
		}
		return nil, status.Error(codes.Internal, err.Error())
	}

	return &types.QueryIntegrityRecordResponse{
		Set:    integritySet,
		Record: record,
	}, nil
}
