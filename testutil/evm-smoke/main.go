package main

import (
	"context"
	"crypto/ecdsa"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"math/big"
	"os"
	"path/filepath"
	"strings"
	"time"

	_ "github.com/Kudora-Labs/kudora/app"

	sdk "github.com/cosmos/cosmos-sdk/types"
	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	ethtypes "github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
)

const (
	defaultGasPriceWei = int64(1_000_000_000)
	receiptTimeout     = 90 * time.Second
	pollInterval       = 500 * time.Millisecond
	defaultTransferWei = "100000000000000000"
	defaultStoreValue  = "888"
)

type accountInfo struct {
	CosmosAddress string `json:"cosmos_address"`
	EthAddress    string `json:"eth_address"`
	KeyFile       string `json:"key_file"`
}

type transferResult struct {
	ChainIDHex                string `json:"chain_id_hex"`
	SenderAddress             string `json:"sender_address"`
	RecipientAddress          string `json:"recipient_address"`
	TransferValueWei          string `json:"transfer_value_wei"`
	TransactionHash           string `json:"transaction_hash"`
	ReceiptStatus             string `json:"receipt_status"`
	GasUsed                   uint64 `json:"gas_used"`
	EffectiveGasPriceWei      string `json:"effective_gas_price_wei"`
	SenderBalanceBeforeWei    string `json:"sender_balance_before_wei"`
	SenderBalanceAfterWei     string `json:"sender_balance_after_wei"`
	RecipientBalanceBeforeWei string `json:"recipient_balance_before_wei"`
	RecipientBalanceAfterWei  string `json:"recipient_balance_after_wei"`
	NonceBefore               uint64 `json:"nonce_before"`
	NonceAfter                uint64 `json:"nonce_after"`
}

type contractResult struct {
	ChainIDHex               string `json:"chain_id_hex"`
	DeployerAddress          string `json:"deployer_address"`
	DeploymentTxHash         string `json:"deployment_tx_hash"`
	StoreTxHash              string `json:"store_tx_hash"`
	DeploymentReceiptStatus  string `json:"deployment_receipt_status"`
	StoreReceiptStatus       string `json:"store_receipt_status"`
	ContractAddress          string `json:"contract_address"`
	GasUsedDeploy            uint64 `json:"gas_used_deploy"`
	GasUsedStore             uint64 `json:"gas_used_store"`
	EffectiveGasPriceDeploy  string `json:"effective_gas_price_deploy_wei"`
	EffectiveGasPriceStore   string `json:"effective_gas_price_store_wei"`
	NonceBefore              uint64 `json:"nonce_before"`
	NonceAfterDeploy         uint64 `json:"nonce_after_deploy"`
	NonceAfterStore          uint64 `json:"nonce_after_store"`
	InitialValue             string `json:"initial_value"`
	UpdatedValue             string `json:"updated_value"`
	ReceiptLogsCount         int    `json:"receipt_logs_count"`
	LogsValidated            bool   `json:"logs_validated"`
	DeployerBalanceBeforeWei string `json:"deployer_balance_before_wei"`
	DeployerBalanceAfterWei  string `json:"deployer_balance_after_wei"`
}

func main() {
	if len(os.Args) < 2 {
		exitf("usage: %s <create-account|transfer-smoke|contract-smoke> [flags]", filepath.Base(os.Args[0]))
	}

	var err error
	switch os.Args[1] {
	case "create-account":
		err = runCreateAccount(os.Args[2:])
	case "cleanup-home":
		err = runCleanupHome(os.Args[2:])
	case "transfer-smoke":
		err = runTransferSmoke(os.Args[2:])
	case "contract-smoke":
		err = runContractSmoke(os.Args[2:])
	default:
		err = fmt.Errorf("unknown command %q", os.Args[1])
	}

	if err != nil {
		exitf("%v", err)
	}
}

func runCreateAccount(args []string) error {
	fs := flag.NewFlagSet("create-account", flag.ContinueOnError)
	keyFile := fs.String("key-file", "", "path to write the test-only private key")
	infoFile := fs.String("info-file", "", "path to write the public account metadata")

	if err := fs.Parse(args); err != nil {
		return err
	}

	if *keyFile == "" || *infoFile == "" {
		return errors.New("create-account: --key-file and --info-file are required")
	}

	key, err := crypto.GenerateKey()
	if err != nil {
		return fmt.Errorf("create-account: generate key: %w", err)
	}

	info := accountInfo{
		CosmosAddress: sdk.AccAddress(crypto.PubkeyToAddress(key.PublicKey).Bytes()).String(),
		EthAddress:    crypto.PubkeyToAddress(key.PublicKey).Hex(),
		KeyFile:       *keyFile,
	}

	if err := writeFile(*keyFile, []byte(hex.EncodeToString(crypto.FromECDSA(key))), 0o600); err != nil {
		return fmt.Errorf("create-account: write key: %w", err)
	}
	if err := writeJSON(*infoFile, info, 0o644); err != nil {
		return fmt.Errorf("create-account: write info: %w", err)
	}

	fmt.Printf("create-account: PASS (cosmos=%s eth=%s)\n", info.CosmosAddress, info.EthAddress)
	return nil
}

func runCleanupHome(args []string) error {
	fs := flag.NewFlagSet("cleanup-home", flag.ContinueOnError)
	homeDir := fs.String("home-dir", "", "localnet home directory to empty")

	if err := fs.Parse(args); err != nil {
		return err
	}
	if *homeDir == "" {
		return errors.New("cleanup-home: --home-dir is required")
	}

	entries, err := os.ReadDir(*homeDir)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil
		}
		return fmt.Errorf("cleanup-home: read dir: %w", err)
	}

	for _, entry := range entries {
		if err := os.RemoveAll(filepath.Join(*homeDir, entry.Name())); err != nil {
			return fmt.Errorf("cleanup-home: remove %s: %w", entry.Name(), err)
		}
	}

	fmt.Printf("cleanup-home: PASS (%s)\n", *homeDir)
	return nil
}

func runTransferSmoke(args []string) error {
	fs := flag.NewFlagSet("transfer-smoke", flag.ContinueOnError)
	rpcURL := fs.String("rpc-url", "", "JSON-RPC endpoint")
	chainIDFlag := fs.Uint64("chain-id", 0, "expected EVM chain ID")
	senderKeyFile := fs.String("sender-key-file", "", "path to the funded sender key")
	recipientInfoFile := fs.String("recipient-info-file", "", "path to the recipient public account metadata")
	resultFile := fs.String("result-file", "", "path to write the transaction smoke result JSON")
	valueWei := fs.String("value-wei", defaultTransferWei, "value to transfer in wei")

	if err := fs.Parse(args); err != nil {
		return err
	}

	if *rpcURL == "" || *chainIDFlag == 0 || *senderKeyFile == "" || *recipientInfoFile == "" || *resultFile == "" {
		return errors.New("transfer-smoke: --rpc-url, --chain-id, --sender-key-file, --recipient-info-file, and --result-file are required")
	}

	value, err := decimalBigInt(*valueWei)
	if err != nil {
		return fmt.Errorf("transfer-smoke: invalid --value-wei: %w", err)
	}

	client, ctx, cancel, err := dialClient(*rpcURL, receiptTimeout)
	if err != nil {
		return fmt.Errorf("transfer-smoke: %w", err)
	}
	defer cancel()
	defer client.Close()

	chainID, err := ensureChainID(ctx, client, *chainIDFlag)
	if err != nil {
		return fmt.Errorf("transfer-smoke: %w", err)
	}

	senderKey, err := readKey(*senderKeyFile)
	if err != nil {
		return fmt.Errorf("transfer-smoke: read sender key: %w", err)
	}
	recipientInfo, err := readAccountInfo(*recipientInfoFile)
	if err != nil {
		return fmt.Errorf("transfer-smoke: read recipient info: %w", err)
	}

	senderAddress := crypto.PubkeyToAddress(senderKey.PublicKey)
	recipientAddress := common.HexToAddress(recipientInfo.EthAddress)

	nonceBefore, err := client.PendingNonceAt(ctx, senderAddress)
	if err != nil {
		return fmt.Errorf("transfer-smoke: sender nonce before: %w", err)
	}
	senderBalanceBefore, err := client.BalanceAt(ctx, senderAddress, nil)
	if err != nil {
		return fmt.Errorf("transfer-smoke: sender balance before: %w", err)
	}
	recipientBalanceBefore, err := client.BalanceAt(ctx, recipientAddress, nil)
	if err != nil {
		return fmt.Errorf("transfer-smoke: recipient balance before: %w", err)
	}

	gasPrice, err := suggestedGasPrice(ctx, client)
	if err != nil {
		return fmt.Errorf("transfer-smoke: gas price: %w", err)
	}

	tx := ethtypes.NewTx(&ethtypes.LegacyTx{
		Nonce:    nonceBefore,
		To:       &recipientAddress,
		Value:    value,
		Gas:      21_000,
		GasPrice: gasPrice,
	})

	signedTx, err := ethtypes.SignTx(tx, ethtypes.LatestSignerForChainID(chainID), senderKey)
	if err != nil {
		return fmt.Errorf("transfer-smoke: sign tx: %w", err)
	}
	if err := client.SendTransaction(ctx, signedTx); err != nil {
		return fmt.Errorf("transfer-smoke: send tx: %w", err)
	}

	receipt, err := waitForReceipt(ctx, client, signedTx.Hash())
	if err != nil {
		return fmt.Errorf("transfer-smoke: wait receipt: %w", err)
	}
	if receipt.Status != ethtypes.ReceiptStatusSuccessful {
		return fmt.Errorf("transfer-smoke: receipt status = %s, want 0x1", statusHex(receipt.Status))
	}
	if receipt.GasUsed == 0 {
		return errors.New("transfer-smoke: receipt gasUsed is zero")
	}

	nonceAfter, err := client.NonceAt(ctx, senderAddress, nil)
	if err != nil {
		return fmt.Errorf("transfer-smoke: sender nonce after: %w", err)
	}
	if nonceAfter != nonceBefore+1 {
		return fmt.Errorf("transfer-smoke: sender nonce after = %d, want %d", nonceAfter, nonceBefore+1)
	}

	senderBalanceAfter, err := client.BalanceAt(ctx, senderAddress, nil)
	if err != nil {
		return fmt.Errorf("transfer-smoke: sender balance after: %w", err)
	}
	recipientBalanceAfter, err := client.BalanceAt(ctx, recipientAddress, nil)
	if err != nil {
		return fmt.Errorf("transfer-smoke: recipient balance after: %w", err)
	}

	recipientDelta := new(big.Int).Sub(recipientBalanceAfter, recipientBalanceBefore)
	if recipientDelta.Cmp(value) != 0 {
		return fmt.Errorf("transfer-smoke: recipient balance delta = %s, want %s", recipientDelta.String(), value.String())
	}

	effectiveGasPrice := gasPriceForReceipt(receipt, signedTx)
	gasCost := new(big.Int).Mul(new(big.Int).SetUint64(receipt.GasUsed), effectiveGasPrice)
	expectedSenderBalanceAfter := new(big.Int).Sub(senderBalanceBefore, value)
	expectedSenderBalanceAfter.Sub(expectedSenderBalanceAfter, gasCost)
	if senderBalanceAfter.Cmp(expectedSenderBalanceAfter) != 0 {
		return fmt.Errorf("transfer-smoke: sender balance after = %s, want %s", senderBalanceAfter.String(), expectedSenderBalanceAfter.String())
	}

	result := transferResult{
		ChainIDHex:                chainIDHex(chainID),
		SenderAddress:             senderAddress.Hex(),
		RecipientAddress:          recipientAddress.Hex(),
		TransferValueWei:          value.String(),
		TransactionHash:           signedTx.Hash().Hex(),
		ReceiptStatus:             statusHex(receipt.Status),
		GasUsed:                   receipt.GasUsed,
		EffectiveGasPriceWei:      effectiveGasPrice.String(),
		SenderBalanceBeforeWei:    senderBalanceBefore.String(),
		SenderBalanceAfterWei:     senderBalanceAfter.String(),
		RecipientBalanceBeforeWei: recipientBalanceBefore.String(),
		RecipientBalanceAfterWei:  recipientBalanceAfter.String(),
		NonceBefore:               nonceBefore,
		NonceAfter:                nonceAfter,
	}

	if err := writeJSON(*resultFile, result, 0o644); err != nil {
		return fmt.Errorf("transfer-smoke: write result: %w", err)
	}

	fmt.Printf("transfer-smoke: PASS (tx=%s status=%s gasUsed=%d nonce=%d->%d)\n", result.TransactionHash, result.ReceiptStatus, result.GasUsed, result.NonceBefore, result.NonceAfter)
	return nil
}

func runContractSmoke(args []string) error {
	fs := flag.NewFlagSet("contract-smoke", flag.ContinueOnError)
	rpcURL := fs.String("rpc-url", "", "JSON-RPC endpoint")
	chainIDFlag := fs.Uint64("chain-id", 0, "expected EVM chain ID")
	senderKeyFile := fs.String("sender-key-file", "", "path to the funded deployer key")
	resultFile := fs.String("result-file", "", "path to write the contract smoke result JSON")
	storeValueFlag := fs.String("store-value", defaultStoreValue, "uint256 value to store")

	if err := fs.Parse(args); err != nil {
		return err
	}

	if *rpcURL == "" || *chainIDFlag == 0 || *senderKeyFile == "" || *resultFile == "" {
		return errors.New("contract-smoke: --rpc-url, --chain-id, --sender-key-file, and --result-file are required")
	}

	storeValue, err := decimalBigInt(*storeValueFlag)
	if err != nil {
		return fmt.Errorf("contract-smoke: invalid --store-value: %w", err)
	}

	client, ctx, cancel, err := dialClient(*rpcURL, receiptTimeout)
	if err != nil {
		return fmt.Errorf("contract-smoke: %w", err)
	}
	defer cancel()
	defer client.Close()

	chainID, err := ensureChainID(ctx, client, *chainIDFlag)
	if err != nil {
		return fmt.Errorf("contract-smoke: %w", err)
	}

	senderKey, err := readKey(*senderKeyFile)
	if err != nil {
		return fmt.Errorf("contract-smoke: read sender key: %w", err)
	}
	senderAddress := crypto.PubkeyToAddress(senderKey.PublicKey)

	contractABI, err := abi.JSON(strings.NewReader(storageContractABI))
	if err != nil {
		return fmt.Errorf("contract-smoke: parse storage ABI: %w", err)
	}

	senderBalanceBefore, err := client.BalanceAt(ctx, senderAddress, nil)
	if err != nil {
		return fmt.Errorf("contract-smoke: deployer balance before: %w", err)
	}
	nonceBefore, err := client.PendingNonceAt(ctx, senderAddress)
	if err != nil {
		return fmt.Errorf("contract-smoke: deployer nonce before: %w", err)
	}
	gasPrice, err := suggestedGasPrice(ctx, client)
	if err != nil {
		return fmt.Errorf("contract-smoke: gas price: %w", err)
	}

	deployData := storageContractCreationBytecode()
	deployGas, err := client.EstimateGas(ctx, ethereum.CallMsg{
		From:     senderAddress,
		GasPrice: gasPrice,
		Data:     deployData,
	})
	if err != nil {
		return fmt.Errorf("contract-smoke: estimate deploy gas: %w", err)
	}
	deployGasLimit := paddedGasLimit(deployGas)

	deployTx := ethtypes.NewTx(&ethtypes.LegacyTx{
		Nonce:    nonceBefore,
		GasPrice: gasPrice,
		Gas:      deployGasLimit,
		Data:     deployData,
		Value:    big.NewInt(0),
	})

	signedDeployTx, err := ethtypes.SignTx(deployTx, ethtypes.LatestSignerForChainID(chainID), senderKey)
	if err != nil {
		return fmt.Errorf("contract-smoke: sign deploy tx: %w", err)
	}
	if err := client.SendTransaction(ctx, signedDeployTx); err != nil {
		return fmt.Errorf("contract-smoke: send deploy tx: %w", err)
	}

	deployReceipt, err := waitForReceipt(ctx, client, signedDeployTx.Hash())
	if err != nil {
		return fmt.Errorf("contract-smoke: wait deploy receipt: %w", err)
	}
	if deployReceipt.Status != ethtypes.ReceiptStatusSuccessful {
		return fmt.Errorf("contract-smoke: deploy receipt status = %s, want 0x1", statusHex(deployReceipt.Status))
	}
	if deployReceipt.GasUsed == 0 {
		return errors.New("contract-smoke: deploy receipt gasUsed is zero")
	}
	if deployReceipt.ContractAddress == (common.Address{}) {
		return errors.New("contract-smoke: contractAddress missing from deploy receipt")
	}

	nonceAfterDeploy, err := client.NonceAt(ctx, senderAddress, nil)
	if err != nil {
		return fmt.Errorf("contract-smoke: deployer nonce after deploy: %w", err)
	}
	if nonceAfterDeploy != nonceBefore+1 {
		return fmt.Errorf("contract-smoke: deployer nonce after deploy = %d, want %d", nonceAfterDeploy, nonceBefore+1)
	}

	deployedCode, err := client.CodeAt(ctx, deployReceipt.ContractAddress, nil)
	if err != nil {
		return fmt.Errorf("contract-smoke: read deployed code: %w", err)
	}
	if len(deployedCode) == 0 {
		return errors.New("contract-smoke: deployed contract code is empty")
	}

	initialValue, err := callRetrieve(ctx, client, contractABI, senderAddress, deployReceipt.ContractAddress)
	if err != nil {
		return fmt.Errorf("contract-smoke: initial retrieve: %w", err)
	}
	if initialValue.Sign() != 0 {
		return fmt.Errorf("contract-smoke: initial retrieve = %s, want 0", initialValue.String())
	}

	storeData, err := contractABI.Pack("store", storeValue)
	if err != nil {
		return fmt.Errorf("contract-smoke: pack store call: %w", err)
	}
	storeGas, err := client.EstimateGas(ctx, ethereum.CallMsg{
		From:     senderAddress,
		To:       &deployReceipt.ContractAddress,
		GasPrice: gasPrice,
		Data:     storeData,
	})
	if err != nil {
		return fmt.Errorf("contract-smoke: estimate store gas: %w", err)
	}

	storeTx := ethtypes.NewTx(&ethtypes.LegacyTx{
		Nonce:    nonceAfterDeploy,
		To:       &deployReceipt.ContractAddress,
		GasPrice: gasPrice,
		Gas:      paddedGasLimit(storeGas),
		Data:     storeData,
		Value:    big.NewInt(0),
	})
	signedStoreTx, err := ethtypes.SignTx(storeTx, ethtypes.LatestSignerForChainID(chainID), senderKey)
	if err != nil {
		return fmt.Errorf("contract-smoke: sign store tx: %w", err)
	}
	if err := client.SendTransaction(ctx, signedStoreTx); err != nil {
		return fmt.Errorf("contract-smoke: send store tx: %w", err)
	}

	storeReceipt, err := waitForReceipt(ctx, client, signedStoreTx.Hash())
	if err != nil {
		return fmt.Errorf("contract-smoke: wait store receipt: %w", err)
	}
	if storeReceipt.Status != ethtypes.ReceiptStatusSuccessful {
		return fmt.Errorf("contract-smoke: store receipt status = %s, want 0x1", statusHex(storeReceipt.Status))
	}
	if storeReceipt.GasUsed == 0 {
		return errors.New("contract-smoke: store receipt gasUsed is zero")
	}

	nonceAfterStore, err := client.NonceAt(ctx, senderAddress, nil)
	if err != nil {
		return fmt.Errorf("contract-smoke: deployer nonce after store: %w", err)
	}
	if nonceAfterStore != nonceAfterDeploy+1 {
		return fmt.Errorf("contract-smoke: deployer nonce after store = %d, want %d", nonceAfterStore, nonceAfterDeploy+1)
	}

	updatedValue, err := callRetrieve(ctx, client, contractABI, senderAddress, deployReceipt.ContractAddress)
	if err != nil {
		return fmt.Errorf("contract-smoke: updated retrieve: %w", err)
	}
	if updatedValue.Cmp(storeValue) != 0 {
		return fmt.Errorf("contract-smoke: updated retrieve = %s, want %s", updatedValue.String(), storeValue.String())
	}

	senderBalanceAfter, err := client.BalanceAt(ctx, senderAddress, nil)
	if err != nil {
		return fmt.Errorf("contract-smoke: deployer balance after: %w", err)
	}

	deployEffectiveGasPrice := gasPriceForReceipt(deployReceipt, signedDeployTx)
	storeEffectiveGasPrice := gasPriceForReceipt(storeReceipt, signedStoreTx)
	totalGasCost := new(big.Int).Mul(new(big.Int).SetUint64(deployReceipt.GasUsed), deployEffectiveGasPrice)
	totalGasCost.Add(totalGasCost, new(big.Int).Mul(new(big.Int).SetUint64(storeReceipt.GasUsed), storeEffectiveGasPrice))
	expectedSenderBalanceAfter := new(big.Int).Sub(senderBalanceBefore, totalGasCost)
	if senderBalanceAfter.Cmp(expectedSenderBalanceAfter) != 0 {
		return fmt.Errorf("contract-smoke: deployer balance after = %s, want %s", senderBalanceAfter.String(), expectedSenderBalanceAfter.String())
	}

	result := contractResult{
		ChainIDHex:               chainIDHex(chainID),
		DeployerAddress:          senderAddress.Hex(),
		DeploymentTxHash:         signedDeployTx.Hash().Hex(),
		StoreTxHash:              signedStoreTx.Hash().Hex(),
		DeploymentReceiptStatus:  statusHex(deployReceipt.Status),
		StoreReceiptStatus:       statusHex(storeReceipt.Status),
		ContractAddress:          deployReceipt.ContractAddress.Hex(),
		GasUsedDeploy:            deployReceipt.GasUsed,
		GasUsedStore:             storeReceipt.GasUsed,
		EffectiveGasPriceDeploy:  deployEffectiveGasPrice.String(),
		EffectiveGasPriceStore:   storeEffectiveGasPrice.String(),
		NonceBefore:              nonceBefore,
		NonceAfterDeploy:         nonceAfterDeploy,
		NonceAfterStore:          nonceAfterStore,
		InitialValue:             initialValue.String(),
		UpdatedValue:             updatedValue.String(),
		ReceiptLogsCount:         len(storeReceipt.Logs),
		LogsValidated:            false,
		DeployerBalanceBeforeWei: senderBalanceBefore.String(),
		DeployerBalanceAfterWei:  senderBalanceAfter.String(),
	}

	if err := writeJSON(*resultFile, result, 0o644); err != nil {
		return fmt.Errorf("contract-smoke: write result: %w", err)
	}

	fmt.Printf(
		"contract-smoke: PASS (contract=%s deployStatus=%s storeStatus=%s value=%s nonce=%d->%d->%d)\n",
		result.ContractAddress,
		result.DeploymentReceiptStatus,
		result.StoreReceiptStatus,
		result.UpdatedValue,
		result.NonceBefore,
		result.NonceAfterDeploy,
		result.NonceAfterStore,
	)
	return nil
}

func dialClient(rpcURL string, timeout time.Duration) (*ethclient.Client, context.Context, context.CancelFunc, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	client, err := ethclient.DialContext(ctx, rpcURL)
	if err != nil {
		cancel()
		return nil, nil, nil, fmt.Errorf("dial JSON-RPC client: %w", err)
	}
	return client, ctx, cancel, nil
}

func ensureChainID(ctx context.Context, client *ethclient.Client, expected uint64) (*big.Int, error) {
	chainID, err := client.ChainID(ctx)
	if err != nil {
		return nil, fmt.Errorf("query chain ID: %w", err)
	}
	if chainID.Cmp(new(big.Int).SetUint64(expected)) != 0 {
		return nil, fmt.Errorf("chain ID = %s, want %d", chainID.String(), expected)
	}
	return chainID, nil
}

func callRetrieve(ctx context.Context, client *ethclient.Client, contractABI abi.ABI, from common.Address, contractAddress common.Address) (*big.Int, error) {
	callData, err := contractABI.Pack("retrieve")
	if err != nil {
		return nil, err
	}

	output, err := client.CallContract(ctx, ethereum.CallMsg{
		From: from,
		To:   &contractAddress,
		Data: callData,
	}, nil)
	if err != nil {
		return nil, err
	}

	values, err := contractABI.Unpack("retrieve", output)
	if err != nil {
		return nil, err
	}
	if len(values) != 1 {
		return nil, fmt.Errorf("retrieve returned %d values, want 1", len(values))
	}

	switch value := values[0].(type) {
	case *big.Int:
		return new(big.Int).Set(value), nil
	case big.Int:
		return new(big.Int).Set(&value), nil
	default:
		return nil, fmt.Errorf("unexpected retrieve return type %T", values[0])
	}
}

func waitForReceipt(ctx context.Context, client *ethclient.Client, hash common.Hash) (*ethtypes.Receipt, error) {
	for {
		receipt, err := client.TransactionReceipt(ctx, hash)
		if err == nil {
			return receipt, nil
		}
		if errors.Is(err, ethereum.NotFound) || strings.Contains(strings.ToLower(err.Error()), "not found") {
			select {
			case <-ctx.Done():
				return nil, fmt.Errorf("wait for receipt %s: %w", hash.Hex(), ctx.Err())
			case <-time.After(pollInterval):
				continue
			}
		}
		return nil, err
	}
}

func suggestedGasPrice(ctx context.Context, client *ethclient.Client) (*big.Int, error) {
	gasPrice, err := client.SuggestGasPrice(ctx)
	if err != nil {
		return nil, err
	}
	if gasPrice.Sign() <= 0 {
		return big.NewInt(defaultGasPriceWei), nil
	}
	return gasPrice, nil
}

func gasPriceForReceipt(receipt *ethtypes.Receipt, tx *ethtypes.Transaction) *big.Int {
	if receipt.EffectiveGasPrice != nil && receipt.EffectiveGasPrice.Sign() > 0 {
		return new(big.Int).Set(receipt.EffectiveGasPrice)
	}
	return new(big.Int).Set(tx.GasPrice())
}

func paddedGasLimit(estimated uint64) uint64 {
	return estimated + (estimated / 5) + 50_000
}

func readKey(path string) (*ecdsa.PrivateKey, error) {
	bz, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	keyHex := strings.TrimSpace(string(bz))
	return crypto.HexToECDSA(keyHex)
}

func readAccountInfo(path string) (accountInfo, error) {
	var info accountInfo
	bz, err := os.ReadFile(path)
	if err != nil {
		return info, err
	}
	if err := json.Unmarshal(bz, &info); err != nil {
		return info, err
	}
	return info, nil
}

func writeJSON(path string, value any, perm os.FileMode) error {
	bz, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return err
	}
	bz = append(bz, '\n')
	return writeFile(path, bz, perm)
}

func writeFile(path string, bz []byte, perm os.FileMode) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, bz, perm)
}

func decimalBigInt(value string) (*big.Int, error) {
	n, ok := new(big.Int).SetString(value, 10)
	if !ok {
		return nil, fmt.Errorf("invalid decimal integer %q", value)
	}
	return n, nil
}

func chainIDHex(chainID *big.Int) string {
	return fmt.Sprintf("0x%x", chainID)
}

func statusHex(status uint64) string {
	return fmt.Sprintf("0x%x", status)
}

func exitf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	os.Exit(1)
}
