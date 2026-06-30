package types_test

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/Kudora-Labs/kudora/x/integrity/types"
)

func TestCalculateMerkleRootDeterministic(t *testing.T) {
	records := []types.IntegrityRecord{
		{Tag: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", Nonce: "0x0102", Ciphertext: "0x0a0b"},
		{Tag: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", Nonce: "0x0304", Ciphertext: "0x0c0d"},
	}

	rootA, preparedA, err := types.CalculateMerkleRoot(records)
	require.NoError(t, err)

	rootB, preparedB, err := types.CalculateMerkleRoot([]types.IntegrityRecord{
		records[1],
		records[0],
	})
	require.NoError(t, err)

	require.Equal(t, rootA, rootB)
	require.Equal(t, preparedA, preparedB)
	require.Equal(t, `{"tag":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","nonce":"0x0304","ciphertext":"0x0c0d"}`, types.CanonicalLeafJSON(preparedA[0]))
}
