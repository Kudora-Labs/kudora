package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"

	"github.com/Kudora-Labs/kudora/testutil/integritymock"
	integritytypes "github.com/Kudora-Labs/kudora/x/integrity/types"
)

type expectedOutput struct {
	Tenant      string                           `json:"tenant"`
	Type        string                           `json:"type"`
	Period      string                           `json:"period"`
	Root        string                           `json:"root"`
	RecordCount int                              `json:"record_count"`
	SortedTags  []string                         `json:"sorted_tags"`
	Records     []integritytypes.IntegrityRecord `json:"records"`
}

func main() {
	if len(os.Args) < 2 {
		fail("expected subcommand")
	}

	switch os.Args[1] {
	case "build-set":
		runBuildSet(os.Args[2:])
	default:
		fail("unsupported subcommand %q", os.Args[1])
	}
}

func runBuildSet(args []string) {
	fs := flag.NewFlagSet("build-set", flag.ExitOnError)
	tenant := fs.String("tenant", "orbitrum", "tenant namespace")
	integrityType := fs.String("type", "orbitrum.scoring.expert_daily_bundle.v1", "integrity type")
	period := fs.String("period", "2026-06-25", "integrity period")
	recordCount := fs.Int("record-count", 2, "number of encrypted records")
	recordsFile := fs.String("records-file", "", "path to write the records array JSON")
	expectedFile := fs.String("expected-file", "", "path to write the expected summary JSON")
	fs.Parse(args)

	if *recordsFile == "" || *expectedFile == "" {
		fail("--records-file and --expected-file are required")
	}

	mockSet, err := integritymock.BuildMockSet(*recordCount, *tenant, *integrityType, *period)
	if err != nil {
		fail("build mock set: %v", err)
	}

	writeJSON(*recordsFile, mockSet.Records)
	writeJSON(*expectedFile, expectedOutput{
		Tenant:      mockSet.Tenant,
		Type:        mockSet.Type,
		Period:      mockSet.Period,
		Root:        mockSet.Root,
		RecordCount: len(mockSet.Records),
		SortedTags:  mockSet.SortedTags,
		Records:     mockSet.SortedRecords,
	})
}

func writeJSON(path string, value any) {
	payload, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		fail("marshal %s: %v", path, err)
	}
	if err := os.WriteFile(path, payload, 0o644); err != nil {
		fail("write %s: %v", path, err)
	}
}

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	os.Exit(1)
}
