package decorators_test

import (
	"testing"

	sdkmath "cosmossdk.io/math"

	"github.com/cometbft/cometbft/crypto/secp256k1"
	sdk "github.com/cosmos/cosmos-sdk/types"
	banktypes "github.com/cosmos/cosmos-sdk/x/bank/types"
	"github.com/stretchr/testify/suite"

	"github.com/Kudora-Labs/kudora/app/decorators"
)

type AnteTestSuite struct {
	suite.Suite

	ctx sdk.Context
}

func TestAnteTestSuite(t *testing.T) {
	suite.Run(t, new(AnteTestSuite))
}

// Test the change rate decorator with standard edit msgs,
func (s *AnteTestSuite) TestAnteMsgFilterLogic() {
	acc := sdk.AccAddress(secp256k1.GenPrivKey().PubKey().Address())

	// test blocking any BankSend Messages
	ante := decorators.FilterDecorator(&banktypes.MsgSend{})
	msg := banktypes.NewMsgSend(
		acc,
		acc,
		sdk.NewCoins(sdk.NewCoin("stake", sdkmath.NewInt(1))),
	)
	_, err := ante.AnteHandle(s.ctx, decorators.NewMockTx(msg), false, decorators.EmptyAnte)
	s.Require().Error(err)

	// validate other messages go through still (such as MsgMultiSend)
	msgMultiSend := banktypes.NewMsgMultiSend(
		banktypes.NewInput(acc, sdk.NewCoins(sdk.NewCoin("stake", sdkmath.NewInt(1)))),
		[]banktypes.Output{banktypes.NewOutput(acc, sdk.NewCoins(sdk.NewCoin("stake", sdkmath.NewInt(1))))},
	)
	_, err = ante.AnteHandle(s.ctx, decorators.NewMockTx(msgMultiSend), false, decorators.EmptyAnte)
	s.Require().NoError(err)
}

// TestMsgFilterDecoratorCreation tests the creation of MsgFilterDecorator
func (s *AnteTestSuite) TestMsgFilterDecoratorCreation() {
	// Test creating decorator with no blocked types
	decorator := decorators.FilterDecorator()
	s.Require().NotNil(decorator)

	// Test creating decorator with blocked types
	blockedMsg := &banktypes.MsgSend{}
	decorator = decorators.FilterDecorator(blockedMsg)
	s.Require().NotNil(decorator)
}

// TestMsgFilterDecoratorMultipleBlockedTypes tests decorator with multiple blocked message types
func (s *AnteTestSuite) TestMsgFilterDecoratorMultipleBlockedTypes() {
	acc := sdk.AccAddress(secp256k1.GenPrivKey().PubKey().Address())
	
	blockedMsg1 := &banktypes.MsgSend{}
	blockedMsg2 := &banktypes.MsgMultiSend{}
	
	decorator := decorators.FilterDecorator(blockedMsg1, blockedMsg2)
	s.Require().NotNil(decorator)
	
	// Test that both message types are blocked
	msgSend := banktypes.NewMsgSend(
		acc, acc,
		sdk.NewCoins(sdk.NewCoin("stake", sdkmath.NewInt(1))),
	)
	_, err := decorator.AnteHandle(s.ctx, decorators.NewMockTx(msgSend), false, decorators.EmptyAnte)
	s.Require().Error(err, "MsgSend should be blocked")
	
	msgMultiSend := banktypes.NewMsgMultiSend(
		banktypes.NewInput(acc, sdk.NewCoins(sdk.NewCoin("stake", sdkmath.NewInt(1)))),
		[]banktypes.Output{banktypes.NewOutput(acc, sdk.NewCoins(sdk.NewCoin("stake", sdkmath.NewInt(1))))},
	)
	_, err = decorator.AnteHandle(s.ctx, decorators.NewMockTx(msgMultiSend), false, decorators.EmptyAnte)
	s.Require().Error(err, "MsgMultiSend should be blocked")
}

// TestMsgFilterDecoratorWithMixedMessages tests mixed allowed/blocked messages
func (s *AnteTestSuite) TestMsgFilterDecoratorWithMixedMessages() {
	acc := sdk.AccAddress(secp256k1.GenPrivKey().PubKey().Address())
	
	// Block only MsgSend
	decorator := decorators.FilterDecorator(&banktypes.MsgSend{})
	
	// Create mix of allowed and blocked messages
	msgSend := banktypes.NewMsgSend(
		acc, acc,
		sdk.NewCoins(sdk.NewCoin("stake", sdkmath.NewInt(1))),
	)
	msgMultiSend := banktypes.NewMsgMultiSend(
		banktypes.NewInput(acc, sdk.NewCoins(sdk.NewCoin("stake", sdkmath.NewInt(1)))),
		[]banktypes.Output{banktypes.NewOutput(acc, sdk.NewCoins(sdk.NewCoin("stake", sdkmath.NewInt(1))))},
	)
	
	// Transaction with both messages should be blocked
	_, err := decorator.AnteHandle(s.ctx, decorators.NewMockTx(msgMultiSend, msgSend), false, decorators.EmptyAnte)
	s.Require().Error(err, "transaction should be blocked when it contains blocked message")
	
	// Transaction with only allowed messages should pass
	_, err = decorator.AnteHandle(s.ctx, decorators.NewMockTx(msgMultiSend), false, decorators.EmptyAnte)
	s.Require().NoError(err, "transaction with only allowed messages should pass")
}

// TestMsgFilterDecoratorWithEmptyMessages tests behavior with empty message list
func (s *AnteTestSuite) TestMsgFilterDecoratorWithEmptyMessages() {
	decorator := decorators.FilterDecorator(&banktypes.MsgSend{})
	
	// Test with empty transaction
	_, err := decorator.AnteHandle(s.ctx, decorators.NewMockTx(), false, decorators.EmptyAnte)
	s.Require().NoError(err, "empty transaction should not be blocked")
}

// TestMsgFilterDecoratorErrorMessage tests the error message format
func (s *AnteTestSuite) TestMsgFilterDecoratorErrorMessage() {
	acc := sdk.AccAddress(secp256k1.GenPrivKey().PubKey().Address())
	
	decorator := decorators.FilterDecorator(&banktypes.MsgSend{})
	
	msgSend := banktypes.NewMsgSend(
		acc, acc,
		sdk.NewCoins(sdk.NewCoin("stake", sdkmath.NewInt(1))),
	)
	
	_, err := decorator.AnteHandle(s.ctx, decorators.NewMockTx(msgSend), false, decorators.EmptyAnte)
	s.Require().Error(err)
	s.Require().Contains(err.Error(), "tx contains unsupported message types", "error should mention unsupported message types")
}

// TestMsgFilterDecoratorSimulationMode tests behavior in simulation mode
func (s *AnteTestSuite) TestMsgFilterDecoratorSimulationMode() {
	acc := sdk.AccAddress(secp256k1.GenPrivKey().PubKey().Address())
	
	decorator := decorators.FilterDecorator(&banktypes.MsgSend{})
	
	msgSend := banktypes.NewMsgSend(
		acc, acc,
		sdk.NewCoins(sdk.NewCoin("stake", sdkmath.NewInt(1))),
	)
	
	// Test that simulation mode still blocks messages (should behave the same)
	_, err := decorator.AnteHandle(s.ctx, decorators.NewMockTx(msgSend), true, decorators.EmptyAnte)
	s.Require().Error(err, "simulation mode should still block forbidden messages")
}

// TestMsgFilterDecoratorNilNextHandler tests behavior with nil next handler
func (s *AnteTestSuite) TestMsgFilterDecoratorNilNextHandler() {
	acc := sdk.AccAddress(secp256k1.GenPrivKey().PubKey().Address())
	
	decorator := decorators.FilterDecorator()
	
	msgMultiSend := banktypes.NewMsgMultiSend(
		banktypes.NewInput(acc, sdk.NewCoins(sdk.NewCoin("stake", sdkmath.NewInt(1)))),
		[]banktypes.Output{banktypes.NewOutput(acc, sdk.NewCoins(sdk.NewCoin("stake", sdkmath.NewInt(1))))},
	)
	
	// Should panic with nil next handler for allowed messages
	s.Require().Panics(func() {
		decorator.AnteHandle(s.ctx, decorators.NewMockTx(msgMultiSend), false, nil)
	}, "should panic with nil next handler")
}
