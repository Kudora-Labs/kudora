package app

import (
	"testing"

	dbm "github.com/cosmos/cosmos-db"
	clientflags "github.com/cosmos/cosmos-sdk/client/flags"
	"github.com/cosmos/evm/server/flags"

	"cosmossdk.io/log/v2"

	"github.com/cosmos/cosmos-sdk/baseapp"
	"github.com/spf13/viper"
)

func BenchmarkDefaultGenesis(b *testing.B) {
	opts := viper.New()
	opts.Set(flags.EVMChainID, DefaultEVMChainID)
	opts.Set(clientflags.FlagHome, b.TempDir())

	application := New(
		log.NewNopLogger(),
		dbm.NewMemDB(),
		nil,
		true,
		opts,
		baseapp.SetChainID(DefaultChainID),
	)

	for i := 0; i < b.N; i++ {
		_ = application.DefaultGenesis()
	}
}
