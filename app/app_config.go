package app

import (
	"maps"
	"sort"

	wasmtypes "github.com/CosmWasm/wasmd/x/wasm/types"
	cosmosevmutils "github.com/cosmos/evm/utils"
	erc20types "github.com/cosmos/evm/x/erc20/types"
	feemarkettypes "github.com/cosmos/evm/x/feemarket/types"
	vmtypes "github.com/cosmos/evm/x/vm/types"
	corevm "github.com/ethereum/go-ethereum/core/vm"

	authtypes "github.com/cosmos/cosmos-sdk/x/auth/types"
	distrtypes "github.com/cosmos/cosmos-sdk/x/distribution/types"
	govtypes "github.com/cosmos/cosmos-sdk/x/gov/types"
	minttypes "github.com/cosmos/cosmos-sdk/x/mint/types"
	stakingtypes "github.com/cosmos/cosmos-sdk/x/staking/types"
)

var moduleAccPerms = map[string][]string{
	authtypes.FeeCollectorName:     nil,
	distrtypes.ModuleName:          nil,
	minttypes.ModuleName:           {authtypes.Minter},
	stakingtypes.BondedPoolName:    {authtypes.Burner, authtypes.Staking},
	stakingtypes.NotBondedPoolName: {authtypes.Burner, authtypes.Staking},
	govtypes.ModuleName:            {authtypes.Burner},
	vmtypes.ModuleName:             {authtypes.Minter, authtypes.Burner},
	feemarkettypes.ModuleName:      nil,
	erc20types.ModuleName:          {authtypes.Minter, authtypes.Burner},
	wasmtypes.ModuleName:           {authtypes.Burner},
}

// GetMaccPerms returns a copy of the module account permissions.
func GetMaccPerms() map[string][]string {
	return maps.Clone(moduleAccPerms)
}

// BlockedAddresses returns all blocked addresses for bank sends.
func BlockedAddresses() map[string]bool {
	blocked := make(map[string]bool)

	moduleNames := make([]string, 0, len(moduleAccPerms))
	for moduleName := range moduleAccPerms {
		moduleNames = append(moduleNames, moduleName)
	}
	sort.Strings(moduleNames)

	for _, moduleName := range moduleNames {
		blocked[authtypes.NewModuleAddress(moduleName).String()] = true
	}

	precompiles := append([]string{}, vmtypes.AvailableStaticPrecompiles...)
	for _, addr := range corevm.PrecompiledAddressesPrague {
		precompiles = append(precompiles, addr.Hex())
	}

	for _, precompile := range precompiles {
		blocked[cosmosevmutils.Bech32StringFromHexAddress(precompile)] = true
	}

	return blocked
}
