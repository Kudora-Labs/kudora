package types

import (
	"encoding/hex"
	"fmt"
	"regexp"
	"slices"
	"strings"

	errorsmod "cosmossdk.io/errors"
)

var (
	tenantPattern = regexp.MustCompile(`^[a-z0-9._-]+$`)
	typePattern   = regexp.MustCompile(`^[a-z0-9._:-]+$`)
)

func NormalizeCreator(creator string) (string, error) {
	return normalizeAccountAddress(creator, "creator")
}

func NormalizeOwnerAddress(owner string, field string) (string, error) {
	return normalizeAccountAddress(owner, field)
}

func normalizeAccountAddress(value string, field string) (string, error) {
	value = strings.TrimSpace(value)
	if field == "" {
		field = "address"
	}
	if value == "" {
		return "", ErrInvalidSigner.Wrapf("%s address must not be empty", field)
	}
	return value, nil
}

func NormalizeTenant(tenant string) (string, error) {
	tenant = strings.ToLower(strings.TrimSpace(tenant))
	switch {
	case tenant == "":
		return "", ErrInvalidTenant.Wrap("tenant must not be empty")
	case len(tenant) > MaxTenantLength:
		return "", ErrInvalidTenant.Wrapf("tenant exceeds maximum length %d", MaxTenantLength)
	case !tenantPattern.MatchString(tenant):
		return "", ErrInvalidTenant.Wrap("tenant contains unsupported characters")
	default:
		return tenant, nil
	}
}

func NormalizeIntegrityType(integrityType string) (string, error) {
	integrityType = strings.ToLower(strings.TrimSpace(integrityType))
	switch {
	case integrityType == "":
		return "", ErrInvalidType.Wrap("type must not be empty")
	case len(integrityType) > MaxTypeLength:
		return "", ErrInvalidType.Wrapf("type exceeds maximum length %d", MaxTypeLength)
	case !typePattern.MatchString(integrityType):
		return "", ErrInvalidType.Wrap("type contains unsupported characters")
	default:
		return integrityType, nil
	}
}

func NormalizePeriod(period string) (string, error) {
	period = strings.TrimSpace(period)
	switch {
	case period == "":
		return "", ErrInvalidPeriod.Wrap("period must not be empty")
	case len(period) > MaxPeriodLength:
		return "", ErrInvalidPeriod.Wrapf("period exceeds maximum length %d", MaxPeriodLength)
	case strings.ContainsAny(period, "\r\n\t"):
		return "", ErrInvalidPeriod.Wrap("period must not contain control characters")
	default:
		return period, nil
	}
}

func NormalizeRoot(root string) (string, error) {
	return normalizeFixedLengthHex(root, 32, ErrInvalidRoot, "root")
}

func NormalizeTag(tag string) (string, error) {
	return normalizeTag(tag)
}

func normalizeTag(tag string) (string, error) {
	return normalizeFixedLengthHex(tag, 32, ErrInvalidRecord, "tag")
}

func normalizeFixedLengthHex(value string, size int, sentinel error, field string) (string, error) {
	normalized, decoded, err := normalizeHexBytes(value, size)
	if err != nil {
		return "", errorsmod.Wrapf(sentinel, "%s %s", field, err.Error())
	}
	if len(decoded) != size {
		return "", errorsmod.Wrapf(sentinel, "%s must be exactly %d bytes", field, size)
	}
	return normalized, nil
}

func normalizeVariableLengthHex(value string, maxBytes int, sentinel error, field string) (string, int, error) {
	normalized, decoded, err := normalizeHexBytes(value, maxBytes)
	if err != nil {
		return "", 0, errorsmod.Wrapf(sentinel, "%s %s", field, err.Error())
	}
	if len(decoded) == 0 {
		return "", 0, errorsmod.Wrapf(sentinel, "%s must not be empty", field)
	}
	return normalized, len(decoded), nil
}

func normalizeHexBytes(value string, maxBytes int) (string, []byte, error) {
	value = strings.ToLower(strings.TrimSpace(value))
	if !strings.HasPrefix(value, "0x") {
		return "", nil, fmt.Errorf("must start with 0x")
	}
	hexPart := strings.TrimPrefix(value, "0x")
	if hexPart == "" {
		return "", nil, fmt.Errorf("must not be empty")
	}
	if len(hexPart)%2 != 0 {
		return "", nil, fmt.Errorf("must contain an even number of hex characters")
	}
	decoded, err := hex.DecodeString(hexPart)
	if err != nil {
		return "", nil, fmt.Errorf("must be valid lowercase hex")
	}
	if maxBytes > 0 && len(decoded) > maxBytes {
		return "", nil, fmt.Errorf("exceeds maximum size %d bytes", maxBytes)
	}
	return "0x" + hexPart, decoded, nil
}

func PrepareIntegrityRecords(records []IntegrityRecord) ([]IntegrityRecord, int, error) {
	if len(records) == 0 {
		return nil, 0, ErrEmptyRecords
	}
	if len(records) > MaxRecordsPerSet {
		return nil, 0, ErrTooManyRecords.Wrapf("maximum records per set is %d", MaxRecordsPerSet)
	}

	prepared := make([]IntegrityRecord, len(records))
	totalCiphertextBytes := 0
	for i := range records {
		tag, err := normalizeTag(records[i].Tag)
		if err != nil {
			return nil, 0, err
		}
		nonce, _, err := normalizeVariableLengthHex(records[i].Nonce, MaxNonceBytes, ErrInvalidRecord, "nonce")
		if err != nil {
			return nil, 0, err
		}
		ciphertext, ciphertextBytes, err := normalizeVariableLengthHex(records[i].Ciphertext, MaxCiphertextBytes, ErrInvalidRecord, "ciphertext")
		if err != nil {
			return nil, 0, err
		}
		totalCiphertextBytes += ciphertextBytes
		if totalCiphertextBytes > MaxTotalCiphertextBytes {
			return nil, 0, ErrTotalCiphertextTooLarge.Wrapf("maximum total ciphertext size is %d bytes", MaxTotalCiphertextBytes)
		}
		prepared[i] = IntegrityRecord{
			Tag:        tag,
			Nonce:      nonce,
			Ciphertext: ciphertext,
		}
	}

	slices.SortFunc(prepared, func(a, b IntegrityRecord) int {
		return strings.Compare(a.Tag, b.Tag)
	})

	for i := 1; i < len(prepared); i++ {
		if prepared[i-1].Tag == prepared[i].Tag {
			return nil, 0, ErrDuplicateTag.Wrapf("duplicate tag %s", prepared[i].Tag)
		}
	}

	return prepared, totalCiphertextBytes, nil
}
