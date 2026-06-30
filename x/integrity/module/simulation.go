package integrity

import (
	"github.com/Kudora-Labs/kudora/x/integrity/types"
	"github.com/cosmos/cosmos-sdk/types/module"
	simtypes "github.com/cosmos/cosmos-sdk/types/simulation"
)

// GenerateGenesisState creates a randomized GenState of the module.
func (AppModule) GenerateGenesisState(simState *module.SimulationState) {
	accs := make([]string, len(simState.Accounts))
	for i, acc := range simState.Accounts {
		accs[i] = acc.Address.String()
	}
	integrityGenesis := types.GenesisState{
		Params: types.DefaultParams(),
	}
	simState.GenState[types.ModuleName] = simState.Cdc.MustMarshalJSON(&integrityGenesis)
}

// RegisterStoreDecoder registers a decoder.
func (am AppModule) RegisterStoreDecoder(_ simtypes.StoreDecoderRegistry) {}

// WeightedOperations returns no custom simulation operations for the integrity MVP.
func (am AppModule) WeightedOperations(simState module.SimulationState) []simtypes.WeightedOperation {
	return nil
}

// ProposalMsgs returns msgs used for governance proposals for simulations.
func (am AppModule) ProposalMsgs(simState module.SimulationState) []simtypes.WeightedProposalMsg {
	return []simtypes.WeightedProposalMsg{}
}
