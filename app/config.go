package app

import (
	wasmtypes "github.com/CosmWasm/wasmd/x/wasm/types"
	"github.com/cosmos/evm/crypto/hd"
	"github.com/cosmos/evm/utils"

	sdk "github.com/cosmos/cosmos-sdk/types"
)

func init() {
	sdk.DefaultBondDenom = DefaultBaseDenom
	sdk.DefaultPowerReduction = utils.AttoPowerReduction

	accountPubKeyPrefix := AccountAddressPrefix + "pub"
	validatorAddressPrefix := AccountAddressPrefix + "valoper"
	validatorPubKeyPrefix := AccountAddressPrefix + "valoperpub"
	consNodeAddressPrefix := AccountAddressPrefix + "valcons"
	consNodePubKeyPrefix := AccountAddressPrefix + "valconspub"

	cfg := sdk.GetConfig()
	cfg.SetCoinType(ChainCoinType)
	cfg.SetPurpose(sdk.Purpose)
	cfg.SetFullFundraiserPath(hd.BIP44HDPath) //nolint:staticcheck
	cfg.SetBech32PrefixForAccount(AccountAddressPrefix, accountPubKeyPrefix)
	cfg.SetBech32PrefixForValidator(validatorAddressPrefix, validatorPubKeyPrefix)
	cfg.SetBech32PrefixForConsensusNode(consNodeAddressPrefix, consNodePubKeyPrefix)
	cfg.SetAddressVerifier(wasmtypes.VerifyAddressLen())
	cfg.Seal()
}
