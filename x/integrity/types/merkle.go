package types

import (
	"crypto/sha256"
	"encoding/hex"
)

func CalculateMerkleRoot(records []IntegrityRecord) (string, []IntegrityRecord, error) {
	prepared, _, err := PrepareIntegrityRecords(records)
	if err != nil {
		return "", nil, err
	}

	return CalculateMerkleRootFromPreparedRecords(prepared), prepared, nil
}

func CalculateMerkleRootFromPreparedRecords(records []IntegrityRecord) string {
	level := make([][]byte, len(records))
	for i := range records {
		sum := sha256.Sum256([]byte(CanonicalLeafJSON(records[i])))
		level[i] = sum[:]
	}

	for len(level) > 1 {
		if len(level)%2 == 1 {
			level = append(level, level[len(level)-1])
		}

		nextLevel := make([][]byte, 0, len(level)/2)
		for i := 0; i < len(level); i += 2 {
			parentInput := append(append(make([]byte, 0, len(level[i])+len(level[i+1])), level[i]...), level[i+1]...)
			sum := sha256.Sum256(parentInput)
			nextLevel = append(nextLevel, sum[:])
		}
		level = nextLevel
	}

	return "0x" + hex.EncodeToString(level[0])
}
