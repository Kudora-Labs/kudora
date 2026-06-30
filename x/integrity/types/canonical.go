package types

import "fmt"

// CanonicalLeafJSON returns the exact canonical JSON leaf representation used for Merkle hashing.
func CanonicalLeafJSON(record IntegrityRecord) string {
	return fmt.Sprintf(
		`{"tag":"%s","nonce":"%s","ciphertext":"%s"}`,
		record.Tag,
		record.Nonce,
		record.Ciphertext,
	)
}
