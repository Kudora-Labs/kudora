package integritymock

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"slices"

	integritytypes "github.com/Kudora-Labs/kudora/x/integrity/types"
)

const (
	TestEncryptionKeyMaterial = "kudora-phase12-integrity-test-encryption-key"
	TestTagKeyMaterial        = "kudora-phase12-integrity-test-tag-key"
)

type OrbitrumLikeScore struct {
	SectionType string `json:"sectionType"`
	ScoreScaled int64  `json:"scoreScaled"`
	Scale       int64  `json:"scale"`
}

type OrbitrumLikeProject struct {
	ProjectID int                 `json:"projectId"`
	Scores    []OrbitrumLikeScore `json:"scores"`
}

type OrbitrumLikeBundle struct {
	LegitimateID int                   `json:"legitimateId"`
	Day          string                `json:"day"`
	Projects     []OrbitrumLikeProject `json:"projects"`
}

type MockSet struct {
	Tenant        string
	Type          string
	Period        string
	Root          string
	Records       []integritytypes.IntegrityRecord
	SortedRecords []integritytypes.IntegrityRecord
	SortedTags    []string
	Plaintexts    []OrbitrumLikeBundle
}

func BuildMockSet(recordCount int, tenant, integrityType, period string) (MockSet, error) {
	if recordCount <= 0 {
		return MockSet{}, fmt.Errorf("recordCount must be positive")
	}

	records := make([]integritytypes.IntegrityRecord, 0, recordCount)
	plaintexts := make([]OrbitrumLikeBundle, 0, recordCount)
	for i := 0; i < recordCount; i++ {
		plaintext := OrbitrumLikeBundle{
			LegitimateID: 123 + i,
			Day:          period,
			Projects: []OrbitrumLikeProject{
				{
					ProjectID: 789 + i,
					Scores: []OrbitrumLikeScore{
						{SectionType: "business_value", ScoreScaled: 84250000 + int64(i), Scale: 1000000},
						{SectionType: "team_integrity", ScoreScaled: 91000000 + int64(i), Scale: 1000000},
					},
				},
			},
		}

		record, err := encryptBundle(tenant, integrityType, period, plaintext)
		if err != nil {
			return MockSet{}, err
		}

		records = append(records, record)
		plaintexts = append(plaintexts, plaintext)
	}

	root, sortedRecords, err := integritytypes.CalculateMerkleRoot(records)
	if err != nil {
		return MockSet{}, err
	}

	unsortedRecords := slices.Clone(sortedRecords)
	slices.Reverse(unsortedRecords)

	sortedTags := make([]string, 0, len(sortedRecords))
	for _, record := range sortedRecords {
		sortedTags = append(sortedTags, record.Tag)
	}

	return MockSet{
		Tenant:        tenant,
		Type:          integrityType,
		Period:        period,
		Root:          root,
		Records:       unsortedRecords,
		SortedRecords: sortedRecords,
		SortedTags:    sortedTags,
		Plaintexts:    plaintexts,
	}, nil
}

func DecryptRecord(tenant, integrityType, period string, record integritytypes.IntegrityRecord) (OrbitrumLikeBundle, error) {
	var plaintext OrbitrumLikeBundle

	key := sha256.Sum256([]byte(TestEncryptionKeyMaterial))
	block, err := aes.NewCipher(key[:])
	if err != nil {
		return plaintext, err
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return plaintext, err
	}

	nonce, err := hex.DecodeString(record.Nonce[2:])
	if err != nil {
		return plaintext, err
	}
	ciphertext, err := hex.DecodeString(record.Ciphertext[2:])
	if err != nil {
		return plaintext, err
	}

	payload, err := aead.Open(nil, nonce, ciphertext, []byte(aad(tenant, integrityType, period)))
	if err != nil {
		return plaintext, err
	}
	if err := json.Unmarshal(payload, &plaintext); err != nil {
		return plaintext, err
	}

	return plaintext, nil
}

func encryptBundle(tenant, integrityType, period string, bundle OrbitrumLikeBundle) (integritytypes.IntegrityRecord, error) {
	plaintext, err := json.Marshal(bundle)
	if err != nil {
		return integritytypes.IntegrityRecord{}, err
	}

	key := sha256.Sum256([]byte(TestEncryptionKeyMaterial))
	block, err := aes.NewCipher(key[:])
	if err != nil {
		return integritytypes.IntegrityRecord{}, err
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return integritytypes.IntegrityRecord{}, err
	}

	nonceSeed := sha256.Sum256([]byte(fmt.Sprintf("nonce:%s:%s:%s:%d", tenant, integrityType, period, bundle.LegitimateID)))
	nonce := nonceSeed[:aead.NonceSize()]
	ciphertext := aead.Seal(nil, nonce, plaintext, []byte(aad(tenant, integrityType, period)))

	tagMac := hmac.New(sha256.New, []byte(TestTagKeyMaterial))
	if _, err := tagMac.Write([]byte(fmt.Sprintf("%d", bundle.LegitimateID))); err != nil {
		return integritytypes.IntegrityRecord{}, err
	}
	tag := tagMac.Sum(nil)

	return integritytypes.IntegrityRecord{
		Tag:        "0x" + hex.EncodeToString(tag),
		Nonce:      "0x" + hex.EncodeToString(nonce),
		Ciphertext: "0x" + hex.EncodeToString(ciphertext),
	}, nil
}

func aad(tenant, integrityType, period string) string {
	return tenant + "|" + integrityType + "|" + period
}
