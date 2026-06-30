package types_test

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/Kudora-Labs/kudora/x/integrity/types"
)

func TestPrepareIntegrityRecords(t *testing.T) {
	t.Run("sorts and normalizes records", func(t *testing.T) {
		prepared, _, err := types.PrepareIntegrityRecords([]types.IntegrityRecord{
			{Tag: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", Nonce: "0xAABB", Ciphertext: "0xCCDD"},
			{Tag: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", Nonce: "0x0102", Ciphertext: "0x0304"},
		})
		require.NoError(t, err)
		require.Len(t, prepared, 2)
		require.Equal(t, "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", prepared[0].Tag)
		require.Equal(t, "0xaabb", prepared[1].Nonce)
		require.Equal(t, "0xccdd", prepared[1].Ciphertext)
	})

	t.Run("rejects duplicate tags", func(t *testing.T) {
		_, _, err := types.PrepareIntegrityRecords([]types.IntegrityRecord{
			{Tag: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", Nonce: "0x0102", Ciphertext: "0x0304"},
			{Tag: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", Nonce: "0x0506", Ciphertext: "0x0708"},
		})
		require.ErrorIs(t, err, types.ErrDuplicateTag)
	})
}

func TestNormalizeFieldConstraints(t *testing.T) {
	_, err := types.NormalizeTenant("Orbitrum")
	require.NoError(t, err)

	_, err = types.NormalizeRoot("0x1234")
	require.ErrorIs(t, err, types.ErrInvalidRoot)

	_, _, err = types.PrepareIntegrityRecords([]types.IntegrityRecord{
		{Tag: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", Nonce: "0x123", Ciphertext: "0x0304"},
	})
	require.ErrorIs(t, err, types.ErrInvalidRecord)
}
