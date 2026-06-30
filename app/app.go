package app

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	goruntime "runtime"

	"github.com/CosmWasm/wasmd/x/wasm"
	wasmkeeper "github.com/CosmWasm/wasmd/x/wasm/keeper"
	wasmtypes "github.com/CosmWasm/wasmd/x/wasm/types"
	"github.com/ethereum/go-ethereum/common"
	"github.com/spf13/cast"

	_ "github.com/ethereum/go-ethereum/eth/tracers/js"
	_ "github.com/ethereum/go-ethereum/eth/tracers/native"

	abci "github.com/cometbft/cometbft/abci/types"
	cmtproto "github.com/cometbft/cometbft/proto/tendermint/types"

	dbm "github.com/cosmos/cosmos-db"
	evmante "github.com/cosmos/evm/ante"
	antetypes "github.com/cosmos/evm/ante/types"
	evmencoding "github.com/cosmos/evm/encoding"
	evmaddress "github.com/cosmos/evm/encoding/address"
	evmmempool "github.com/cosmos/evm/mempool"
	cosmosevmserver "github.com/cosmos/evm/server"
	srvflags "github.com/cosmos/evm/server/flags"
	evmutils "github.com/cosmos/evm/utils"
	"github.com/cosmos/evm/x/erc20"
	erc20keeper "github.com/cosmos/evm/x/erc20/keeper"
	erc20types "github.com/cosmos/evm/x/erc20/types"
	"github.com/cosmos/evm/x/feemarket"
	feemarketkeeper "github.com/cosmos/evm/x/feemarket/keeper"
	feemarkettypes "github.com/cosmos/evm/x/feemarket/types"
	"github.com/cosmos/evm/x/vm"
	evmkeeper "github.com/cosmos/evm/x/vm/keeper"
	vmrunner "github.com/cosmos/evm/x/vm/runner"
	evmtypes "github.com/cosmos/evm/x/vm/types"
	"github.com/cosmos/gogoproto/proto"
	ibcexported "github.com/cosmos/ibc-go/v11/modules/core/exported"
	ibckeeper "github.com/cosmos/ibc-go/v11/modules/core/keeper"

	reflectionv1 "cosmossdk.io/api/cosmos/reflection/v1"
	clienthelpers "cosmossdk.io/client/v2/helpers"
	"cosmossdk.io/log/v2"

	"github.com/cosmos/cosmos-sdk/baseapp"
	"github.com/cosmos/cosmos-sdk/baseapp/txnrunner"
	"github.com/cosmos/cosmos-sdk/client"
	"github.com/cosmos/cosmos-sdk/client/flags"
	"github.com/cosmos/cosmos-sdk/client/grpc/cmtservice"
	"github.com/cosmos/cosmos-sdk/client/grpc/node"
	"github.com/cosmos/cosmos-sdk/codec"
	codectypes "github.com/cosmos/cosmos-sdk/codec/types"
	"github.com/cosmos/cosmos-sdk/runtime"
	runtimeservices "github.com/cosmos/cosmos-sdk/runtime/services"
	sdkserver "github.com/cosmos/cosmos-sdk/server"
	"github.com/cosmos/cosmos-sdk/server/api"
	serverconfig "github.com/cosmos/cosmos-sdk/server/config"
	servertypes "github.com/cosmos/cosmos-sdk/server/types"
	storetypes "github.com/cosmos/cosmos-sdk/store/v2/types"
	testdata_pulsar "github.com/cosmos/cosmos-sdk/testutil/testdata/testpb"
	sdk "github.com/cosmos/cosmos-sdk/types"
	sdkmempool "github.com/cosmos/cosmos-sdk/types/mempool"
	"github.com/cosmos/cosmos-sdk/types/module"
	"github.com/cosmos/cosmos-sdk/types/msgservice"
	signingtypes "github.com/cosmos/cosmos-sdk/types/tx/signing"
	"github.com/cosmos/cosmos-sdk/version"
	"github.com/cosmos/cosmos-sdk/x/auth"
	authkeeper "github.com/cosmos/cosmos-sdk/x/auth/keeper"
	"github.com/cosmos/cosmos-sdk/x/auth/posthandler"
	authsims "github.com/cosmos/cosmos-sdk/x/auth/simulation"
	authtx "github.com/cosmos/cosmos-sdk/x/auth/tx"
	txmodule "github.com/cosmos/cosmos-sdk/x/auth/tx/config"
	authtypes "github.com/cosmos/cosmos-sdk/x/auth/types"
	"github.com/cosmos/cosmos-sdk/x/auth/vesting"
	vestingtypes "github.com/cosmos/cosmos-sdk/x/auth/vesting/types"
	"github.com/cosmos/cosmos-sdk/x/authz"
	authzkeeper "github.com/cosmos/cosmos-sdk/x/authz/keeper"
	authzmodule "github.com/cosmos/cosmos-sdk/x/authz/module"
	"github.com/cosmos/cosmos-sdk/x/bank"
	bankkeeper "github.com/cosmos/cosmos-sdk/x/bank/keeper"
	banktypes "github.com/cosmos/cosmos-sdk/x/bank/types"
	"github.com/cosmos/cosmos-sdk/x/consensus"
	consensusparamkeeper "github.com/cosmos/cosmos-sdk/x/consensus/keeper"
	consensusparamtypes "github.com/cosmos/cosmos-sdk/x/consensus/types"
	distr "github.com/cosmos/cosmos-sdk/x/distribution"
	distrkeeper "github.com/cosmos/cosmos-sdk/x/distribution/keeper"
	distrtypes "github.com/cosmos/cosmos-sdk/x/distribution/types"
	"github.com/cosmos/cosmos-sdk/x/evidence"
	evidencekeeper "github.com/cosmos/cosmos-sdk/x/evidence/keeper"
	evidencetypes "github.com/cosmos/cosmos-sdk/x/evidence/types"
	"github.com/cosmos/cosmos-sdk/x/feegrant"
	feegrantkeeper "github.com/cosmos/cosmos-sdk/x/feegrant/keeper"
	feegrantmodule "github.com/cosmos/cosmos-sdk/x/feegrant/module"
	"github.com/cosmos/cosmos-sdk/x/genutil"
	genutiltypes "github.com/cosmos/cosmos-sdk/x/genutil/types"
	"github.com/cosmos/cosmos-sdk/x/gov"
	govkeeper "github.com/cosmos/cosmos-sdk/x/gov/keeper"
	govtypes "github.com/cosmos/cosmos-sdk/x/gov/types"
	"github.com/cosmos/cosmos-sdk/x/mint"
	mintkeeper "github.com/cosmos/cosmos-sdk/x/mint/keeper"
	minttypes "github.com/cosmos/cosmos-sdk/x/mint/types"
	"github.com/cosmos/cosmos-sdk/x/slashing"
	slashingkeeper "github.com/cosmos/cosmos-sdk/x/slashing/keeper"
	slashingtypes "github.com/cosmos/cosmos-sdk/x/slashing/types"
	"github.com/cosmos/cosmos-sdk/x/staking"
	stakingkeeper "github.com/cosmos/cosmos-sdk/x/staking/keeper"
	stakingtypes "github.com/cosmos/cosmos-sdk/x/staking/types"
	"github.com/cosmos/cosmos-sdk/x/upgrade"
	upgradekeeper "github.com/cosmos/cosmos-sdk/x/upgrade/keeper"
	upgradetypes "github.com/cosmos/cosmos-sdk/x/upgrade/types"
	corevm "github.com/ethereum/go-ethereum/core/vm"

	"github.com/Kudora-Labs/kudora/docs"
	integritykeeper "github.com/Kudora-Labs/kudora/x/integrity/keeper"
	integritymodule "github.com/Kudora-Labs/kudora/x/integrity/module"
	integritytypes "github.com/Kudora-Labs/kudora/x/integrity/types"
)

const (
	Name                 = "kudora"
	AccountAddressPrefix = "kudo"
	ChainCoinType        = 60
)

var DefaultNodeHome string

var (
	_ runtime.AppI                = (*App)(nil)
	_ cosmosevmserver.Application = (*App)(nil)
)

// App extends a Cosmos SDK BaseApp with the minimal upstream-aligned Cosmos EVM runtime.
type App struct {
	*baseapp.BaseApp

	legacyAmino       *codec.LegacyAmino
	appCodec          codec.Codec
	interfaceRegistry codectypes.InterfaceRegistry
	txConfig          client.TxConfig

	pendingTxListeners []evmante.PendingTxListener

	keys  map[string]*storetypes.KVStoreKey
	oKeys map[string]*storetypes.ObjectStoreKey

	AccountKeeper         authkeeper.AccountKeeper
	BankKeeper            bankkeeper.Keeper
	StakingKeeper         *stakingkeeper.Keeper
	SlashingKeeper        slashingkeeper.Keeper
	MintKeeper            mintkeeper.Keeper
	DistrKeeper           distrkeeper.Keeper
	GovKeeper             govkeeper.Keeper
	UpgradeKeeper         *upgradekeeper.Keeper
	AuthzKeeper           authzkeeper.Keeper
	EvidenceKeeper        evidencekeeper.Keeper
	FeeGrantKeeper        feegrantkeeper.Keeper
	ConsensusParamsKeeper consensusparamkeeper.Keeper

	IBCKeeper *ibckeeper.Keeper

	FeeMarketKeeper feemarketkeeper.Keeper
	EVMKeeper       *evmkeeper.Keeper
	Erc20Keeper     erc20keeper.Keeper
	WasmKeeper      wasmkeeper.Keeper
	IntegrityKeeper integritykeeper.Keeper
	EVMMempool      sdkmempool.ExtMempool

	ModuleManager      *module.Manager
	BasicModuleManager module.BasicManager
	sm                 *module.SimulationManager
	configurator       module.Configurator
}

func init() {
	clienthelpers.EnvPrefix = Name

	var err error
	DefaultNodeHome, err = clienthelpers.GetNodeHomeDirectory("." + Name)
	if err != nil {
		panic(err)
	}
}

// New returns a reference to an initialized App.
func New(
	logger log.Logger,
	db dbm.DB,
	_ io.Writer,
	loadLatest bool,
	appOpts servertypes.AppOptions,
	baseAppOptions ...func(*baseapp.BaseApp),
) *App {
	evmChainID := cast.ToUint64(appOpts.Get(srvflags.EVMChainID))
	if evmChainID == 0 {
		evmChainID = DefaultEVMChainID
	}

	encodingConfig := evmencoding.MakeConfig(evmChainID)
	appCodec := encodingConfig.Codec
	legacyAmino := encodingConfig.Amino
	interfaceRegistry := encodingConfig.InterfaceRegistry
	txConfig := encodingConfig.TxConfig
	txDecoder := txConfig.TxDecoder()

	baseAppOptions = append(baseAppOptions, baseapp.SetOptimisticExecution())

	bApp := baseapp.NewBaseApp(Name, logger, db, txDecoder, baseAppOptions...)
	bApp.SetVersion(version.Version)
	bApp.SetInterfaceRegistry(interfaceRegistry)
	bApp.SetTxEncoder(txConfig.TxEncoder())
	bApp.SetDisableBlockGasMeter(true)

	keys := storetypes.NewKVStoreKeys(
		authtypes.StoreKey,
		banktypes.StoreKey,
		stakingtypes.StoreKey,
		minttypes.StoreKey,
		distrtypes.StoreKey,
		slashingtypes.StoreKey,
		govtypes.StoreKey,
		consensusparamtypes.StoreKey,
		upgradetypes.StoreKey,
		feegrant.StoreKey,
		evidencetypes.StoreKey,
		authzkeeper.StoreKey,
		ibcexported.StoreKey,
		evmtypes.StoreKey,
		feemarkettypes.StoreKey,
		erc20types.StoreKey,
		wasmtypes.StoreKey,
		integritytypes.StoreKey,
	)
	oKeys := storetypes.NewObjectStoreKeys(banktypes.ObjectStoreKey, evmtypes.ObjectKey)

	nonTransientKeys := make([]storetypes.StoreKey, 0, len(keys)+len(oKeys))
	for _, key := range keys {
		nonTransientKeys = append(nonTransientKeys, key)
	}
	for _, key := range oKeys {
		nonTransientKeys = append(nonTransientKeys, key)
	}

	if err := bApp.RegisterStreamingServices(appOpts, keys); err != nil {
		fmt.Printf("failed to load state streaming: %s", err)
		os.Exit(1)
	}

	app := &App{
		BaseApp:           bApp,
		legacyAmino:       legacyAmino,
		appCodec:          appCodec,
		interfaceRegistry: interfaceRegistry,
		txConfig:          txConfig,
		keys:              keys,
		oKeys:             oKeys,
	}

	authority := authtypes.NewModuleAddress(govtypes.ModuleName).String()

	app.ConsensusParamsKeeper = consensusparamkeeper.NewKeeper(
		appCodec,
		runtime.NewKVStoreService(keys[consensusparamtypes.StoreKey]),
		authority,
		runtime.EventService{},
	)
	bApp.SetParamStore(app.ConsensusParamsKeeper.ParamsStore)

	app.AccountKeeper = authkeeper.NewAccountKeeper(
		appCodec,
		runtime.NewKVStoreService(keys[authtypes.StoreKey]),
		authtypes.ProtoBaseAccount,
		GetMaccPerms(),
		evmaddress.NewEvmCodec(sdk.GetConfig().GetBech32AccountAddrPrefix()),
		sdk.GetConfig().GetBech32AccountAddrPrefix(),
		authority,
	)

	app.BankKeeper = bankkeeper.NewBaseKeeper(
		appCodec,
		runtime.NewKVStoreService(keys[banktypes.StoreKey]),
		app.AccountKeeper,
		BlockedAddresses(),
		authority,
		logger,
	).WithObjStoreKey(oKeys[banktypes.ObjectStoreKey])

	enabledSignModes := append(authtx.DefaultSignModes, signingtypes.SignMode_SIGN_MODE_TEXTUAL) //nolint:gocritic
	txConfigOpts := authtx.ConfigOptions{
		EnabledSignModes:           enabledSignModes,
		TextualCoinMetadataQueryFn: txmodule.NewBankKeeperCoinMetadataQueryFn(app.BankKeeper),
	}
	updatedTxConfig, err := authtx.NewTxConfigWithOptions(appCodec, txConfigOpts)
	if err != nil {
		panic(err)
	}
	app.txConfig = updatedTxConfig
	bApp.SetTxEncoder(updatedTxConfig.TxEncoder())

	app.StakingKeeper = stakingkeeper.NewKeeper(
		appCodec,
		runtime.NewKVStoreService(keys[stakingtypes.StoreKey]),
		app.AccountKeeper,
		app.BankKeeper,
		authority,
		evmaddress.NewEvmCodec(sdk.GetConfig().GetBech32ValidatorAddrPrefix()),
		evmaddress.NewEvmCodec(sdk.GetConfig().GetBech32ConsensusAddrPrefix()),
	)

	app.MintKeeper = mintkeeper.NewKeeper(
		appCodec,
		runtime.NewKVStoreService(keys[minttypes.StoreKey]),
		app.StakingKeeper,
		app.AccountKeeper,
		app.BankKeeper,
		authtypes.FeeCollectorName,
		authority,
	)

	app.DistrKeeper = distrkeeper.NewKeeper(
		appCodec,
		runtime.NewKVStoreService(keys[distrtypes.StoreKey]),
		app.AccountKeeper,
		app.BankKeeper,
		app.StakingKeeper,
		authtypes.FeeCollectorName,
		authority,
	)

	app.SlashingKeeper = slashingkeeper.NewKeeper(
		appCodec,
		app.LegacyAmino(),
		runtime.NewKVStoreService(keys[slashingtypes.StoreKey]),
		app.StakingKeeper,
		authority,
	)

	app.FeeGrantKeeper = feegrantkeeper.NewKeeper(
		appCodec,
		runtime.NewKVStoreService(keys[feegrant.StoreKey]),
		app.AccountKeeper,
	)

	app.StakingKeeper.SetHooks(
		stakingtypes.NewMultiStakingHooks(app.DistrKeeper.Hooks(), app.SlashingKeeper.Hooks()),
	)

	app.AuthzKeeper = authzkeeper.NewKeeper(
		runtime.NewKVStoreService(keys[authzkeeper.StoreKey]),
		appCodec,
		app.MsgServiceRouter(),
		app.AccountKeeper,
	)

	skipUpgradeHeights := map[int64]bool{}
	for _, height := range cast.ToIntSlice(appOpts.Get(sdkserver.FlagUnsafeSkipUpgrades)) {
		skipUpgradeHeights[int64(height)] = true
	}
	homePath := cast.ToString(appOpts.Get(flags.FlagHome))
	app.UpgradeKeeper = upgradekeeper.NewKeeper(
		skipUpgradeHeights,
		runtime.NewKVStoreService(keys[upgradetypes.StoreKey]),
		appCodec,
		homePath,
		app.BaseApp,
		authority,
	)

	app.IBCKeeper = ibckeeper.NewKeeper(
		appCodec,
		runtime.NewKVStoreService(keys[ibcexported.StoreKey]),
		app.UpgradeKeeper,
		authority,
	)

	wasmNodeConfig, err := wasm.ReadNodeConfig(appOpts)
	if err != nil {
		panic(fmt.Sprintf("error while reading wasm config: %s", err))
	}

	govConfig := govtypes.DefaultConfig()
	govKeeper := govkeeper.NewKeeper(
		appCodec,
		runtime.NewKVStoreService(keys[govtypes.StoreKey]),
		app.AccountKeeper,
		app.BankKeeper,
		app.DistrKeeper,
		app.MsgServiceRouter(),
		govConfig,
		authority,
		govkeeper.NewDefaultCalculateVoteResultsAndVotingPower(app.StakingKeeper),
	)
	app.GovKeeper = *govKeeper.SetHooks(govtypes.NewMultiGovHooks())

	evidenceKeeper := evidencekeeper.NewKeeper(
		appCodec,
		runtime.NewKVStoreService(keys[evidencetypes.StoreKey]),
		app.StakingKeeper,
		app.SlashingKeeper,
		app.AccountKeeper.AddressCodec(),
		runtime.ProvideCometInfoService(),
	)
	app.EvidenceKeeper = *evidenceKeeper

	app.FeeMarketKeeper = feemarketkeeper.NewKeeper(
		appCodec,
		authtypes.NewModuleAddress(govtypes.ModuleName),
		keys[feemarkettypes.StoreKey],
	)

	tracer := cast.ToString(appOpts.Get(srvflags.EVMTracer))
	app.EVMKeeper = evmkeeper.NewKeeper(
		appCodec,
		keys[evmtypes.StoreKey],
		oKeys[evmtypes.ObjectKey],
		nonTransientKeys,
		authtypes.NewModuleAddress(govtypes.ModuleName),
		app.AccountKeeper,
		app.BankKeeper,
		app.StakingKeeper,
		app.FeeMarketKeeper,
		&app.ConsensusParamsKeeper,
		&app.Erc20Keeper,
		evmChainID,
		tracer,
	).WithStaticPrecompiles(map[common.Address]corevm.PrecompiledContract(kudoraStaticPrecompiles()))

	app.EVMKeeper.EnableVirtualFeeCollection()

	app.Erc20Keeper = erc20keeper.NewKeeper(
		keys[erc20types.StoreKey],
		appCodec,
		authtypes.NewModuleAddress(govtypes.ModuleName),
		app.AccountKeeper,
		app.BankKeeper,
		app.EVMKeeper,
		app.StakingKeeper,
		nil,
	)

	app.WasmKeeper = wasmkeeper.NewKeeper(
		appCodec,
		runtime.NewKVStoreService(keys[wasmtypes.StoreKey]),
		app.AccountKeeper,
		app.BankKeeper,
		app.StakingKeeper,
		distrkeeper.NewQuerier(app.DistrKeeper),
		app.IBCKeeper.ChannelKeeper,
		app.IBCKeeper.ChannelKeeper,
		app.IBCKeeper.ChannelKeeperV2,
		disabledTransferPortSource{},
		app.MsgServiceRouter(),
		app.GRPCQueryRouter(),
		filepath.Join(homePath, "wasm"),
		wasmNodeConfig,
		wasmtypes.VMConfig{},
		wasmkeeper.BuiltInCapabilities(),
		authority,
		kudoraWasmKeeperOptions()...,
	)

	app.IntegrityKeeper = integritykeeper.NewKeeper(
		runtime.NewKVStoreService(keys[integritytypes.StoreKey]),
		appCodec,
		app.AccountKeeper.AddressCodec(),
		authtypes.NewModuleAddress(govtypes.ModuleName),
		app.BankKeeper,
	)

	vmModule := vm.NewAppModule(app.EVMKeeper, app.AccountKeeper, app.BankKeeper, app.AccountKeeper.AddressCodec())

	app.ModuleManager = module.NewManager(
		genutil.NewAppModule(app.AccountKeeper, app.StakingKeeper, app, app.txConfig),
		auth.NewAppModule(appCodec, app.AccountKeeper, authsims.RandomGenesisAccounts, nil),
		bank.NewAppModule(appCodec, app.BankKeeper, app.AccountKeeper, nil),
		integritymodule.NewAppModule(appCodec, app.IntegrityKeeper, app.AccountKeeper, app.BankKeeper),
		feegrantmodule.NewAppModule(appCodec, app.AccountKeeper, app.BankKeeper, app.FeeGrantKeeper, app.interfaceRegistry),
		gov.NewAppModule(appCodec, &app.GovKeeper, app.AccountKeeper, app.BankKeeper, nil),
		mint.NewAppModule(appCodec, app.MintKeeper, app.AccountKeeper, nil, nil),
		slashing.NewAppModule(appCodec, app.SlashingKeeper, app.AccountKeeper, app.BankKeeper, app.StakingKeeper, nil, app.interfaceRegistry),
		distr.NewAppModule(appCodec, app.DistrKeeper, app.AccountKeeper, app.BankKeeper, app.StakingKeeper, nil),
		staking.NewAppModule(appCodec, app.StakingKeeper, app.AccountKeeper, app.BankKeeper, nil),
		upgrade.NewAppModule(app.UpgradeKeeper, app.AccountKeeper.AddressCodec()),
		evidence.NewAppModule(app.EvidenceKeeper),
		authzmodule.NewAppModule(appCodec, app.AuthzKeeper, app.AccountKeeper, app.BankKeeper, app.interfaceRegistry),
		consensus.NewAppModule(appCodec, app.ConsensusParamsKeeper),
		vesting.NewAppModule(app.AccountKeeper, app.BankKeeper),
		vmModule,
		feemarket.NewAppModule(app.FeeMarketKeeper),
		erc20.NewAppModule(app.Erc20Keeper, app.AccountKeeper),
		wasm.NewAppModule(appCodec, &app.WasmKeeper, app.StakingKeeper, app.AccountKeeper, app.BankKeeper, app.MsgServiceRouter(), nil),
	)

	app.BasicModuleManager = module.NewBasicManagerFromManager(
		app.ModuleManager,
		map[string]module.AppModuleBasic{
			genutiltypes.ModuleName: genutil.NewAppModuleBasic(genutiltypes.DefaultMessageValidator),
			stakingtypes.ModuleName: staking.AppModuleBasic{},
			govtypes.ModuleName:     gov.NewAppModuleBasic(nil),
		},
	)
	app.BasicModuleManager.RegisterLegacyAminoCodec(legacyAmino)
	app.BasicModuleManager.RegisterInterfaces(interfaceRegistry)

	app.ModuleManager.SetOrderPreBlockers(
		upgradetypes.ModuleName,
		authtypes.ModuleName,
		evmtypes.ModuleName,
	)

	app.ModuleManager.SetOrderBeginBlockers(
		minttypes.ModuleName,
		erc20types.ModuleName,
		feemarkettypes.ModuleName,
		evmtypes.ModuleName,
		distrtypes.ModuleName,
		slashingtypes.ModuleName,
		evidencetypes.ModuleName,
		stakingtypes.ModuleName,
		authtypes.ModuleName,
		banktypes.ModuleName,
		integritytypes.ModuleName,
		govtypes.ModuleName,
		genutiltypes.ModuleName,
		authz.ModuleName,
		feegrant.ModuleName,
		consensusparamtypes.ModuleName,
		vestingtypes.ModuleName,
		wasmtypes.ModuleName,
	)

	app.ModuleManager.SetOrderEndBlockers(
		banktypes.ModuleName,
		govtypes.ModuleName,
		stakingtypes.ModuleName,
		authtypes.ModuleName,
		integritytypes.ModuleName,
		evmtypes.ModuleName,
		erc20types.ModuleName,
		feemarkettypes.ModuleName,
		distrtypes.ModuleName,
		slashingtypes.ModuleName,
		minttypes.ModuleName,
		genutiltypes.ModuleName,
		evidencetypes.ModuleName,
		authz.ModuleName,
		feegrant.ModuleName,
		upgradetypes.ModuleName,
		consensusparamtypes.ModuleName,
		vestingtypes.ModuleName,
		wasmtypes.ModuleName,
	)

	genesisModuleOrder := []string{
		authtypes.ModuleName,
		banktypes.ModuleName,
		integritytypes.ModuleName,
		distrtypes.ModuleName,
		stakingtypes.ModuleName,
		slashingtypes.ModuleName,
		govtypes.ModuleName,
		minttypes.ModuleName,
		consensusparamtypes.ModuleName,
		evmtypes.ModuleName,
		feemarkettypes.ModuleName,
		erc20types.ModuleName,
		genutiltypes.ModuleName,
		evidencetypes.ModuleName,
		authz.ModuleName,
		feegrant.ModuleName,
		upgradetypes.ModuleName,
		vestingtypes.ModuleName,
		wasmtypes.ModuleName,
	}
	app.ModuleManager.SetOrderInitGenesis(genesisModuleOrder...)
	app.ModuleManager.SetOrderExportGenesis(genesisModuleOrder...)

	app.configurator = module.NewConfigurator(app.appCodec, app.MsgServiceRouter(), app.GRPCQueryRouter())
	if err := app.ModuleManager.RegisterServices(app.configurator); err != nil {
		panic(fmt.Sprintf("failed to register module services: %s", err))
	}

	reflectionSvc, err := runtimeservices.NewReflectionService()
	if err != nil {
		panic(err)
	}
	reflectionv1.RegisterReflectionServiceServer(app.GRPCQueryRouter(), reflectionSvc)
	testdata_pulsar.RegisterQueryServer(app.GRPCQueryRouter(), testdata_pulsar.QueryImpl{})

	overrideModules := map[string]module.AppModuleSimulation{
		authtypes.ModuleName: auth.NewAppModule(app.appCodec, app.AccountKeeper, authsims.RandomGenesisAccounts, nil),
	}
	app.sm = module.NewSimulationManagerFromAppModules(app.ModuleManager.Modules, overrideModules)
	app.sm.RegisterStoreDecoders()

	app.MountKVStores(keys)
	app.MountObjectStores(oKeys)

	maxGasWanted := cast.ToUint64(appOpts.Get(srvflags.EVMMaxTxGasWanted))

	app.SetInitChainer(app.InitChainer)
	app.SetPreBlocker(app.PreBlocker)
	app.SetBeginBlocker(app.BeginBlocker)
	app.SetEndBlocker(app.EndBlocker)
	app.setAnteHandler(app.txConfig, maxGasWanted, wasmNodeConfig)
	if err := app.configureEVMMempool(appOpts, logger); err != nil {
		panic(fmt.Sprintf("failed to configure EVM mempool: %s", err))
	}
	app.setPostHandler()

	if manager := app.SnapshotManager(); manager != nil {
		if err := manager.RegisterExtensions(
			wasmkeeper.NewWasmSnapshotter(app.CommitMultiStore(), &app.WasmKeeper),
		); err != nil {
			panic(fmt.Sprintf("failed to register wasm snapshot extension: %s", err))
		}
	}

	protoFiles, err := proto.MergedRegistry()
	if err != nil {
		panic(err)
	}
	if err := msgservice.ValidateProtoAnnotations(protoFiles); err != nil {
		fmt.Fprintln(os.Stderr, err.Error())
	}

	if loadLatest {
		if err := app.LoadLatestVersion(); err != nil {
			logger.Error("error on loading last version", "error", err)
			os.Exit(1)
		}

		ctx := app.NewContextLegacy(true, cmtproto.Header{
			Height:  app.LastBlockHeight(),
			ChainID: app.ChainID(),
		})
		vmModule.HydrateGlobals(ctx)
		if err := app.WasmKeeper.InitializePinnedCodes(ctx); err != nil {
			panic(fmt.Sprintf("failed to initialize pinned wasm codes: %s", err))
		}
	}

	vmrunner.SetRunner(bApp, txnrunner.NewSTMRunner(
		txDecoder,
		nonTransientKeys,
		min(goruntime.GOMAXPROCS(0), goruntime.NumCPU()),
		true,
		func(ms storetypes.MultiStore) string {
			return app.EVMKeeper.GetParams(sdk.NewContext(ms, cmtproto.Header{}, false, log.NewNopLogger())).EvmDenom
		},
	))

	return app
}

func (app *App) setAnteHandler(txConfig client.TxConfig, maxGasWanted uint64, wasmNodeConfig wasmtypes.NodeConfig) {
	options := evmante.HandlerOptions{
		Cdc:                    app.appCodec,
		AccountKeeper:          app.AccountKeeper,
		BankKeeper:             app.BankKeeper,
		ExtensionOptionChecker: antetypes.HasDynamicFeeExtensionOption,
		EvmKeeper:              app.EVMKeeper,
		FeegrantKeeper:         app.FeeGrantKeeper,
		IBCKeeper:              app.IBCKeeper,
		FeeMarketKeeper:        app.FeeMarketKeeper,
		SignModeHandler:        txConfig.SignModeHandler(),
		SigGasConsumer:         evmante.SigVerificationGasConsumer,
		MaxTxGasWanted:         maxGasWanted,
		DynamicFeeChecker:      true,
		PendingTxListener:      app.onPendingTx,
	}
	if err := options.Validate(); err != nil {
		panic(err)
	}

	anteHandler, err := NewWasmAwareAnteHandler(WasmAwareAnteOptions{
		EVM:                   options,
		NodeConfig:            &wasmNodeConfig,
		WasmKeeper:            &app.WasmKeeper,
		TXCounterStoreService: runtime.NewKVStoreService(app.keys[wasmtypes.StoreKey]),
	})
	if err != nil {
		panic(err)
	}

	app.SetAnteHandler(anteHandler)
}

func (app *App) onPendingTx(hash common.Hash) {
	for _, listener := range app.pendingTxListeners {
		listener(hash)
	}
}

// RegisterPendingTxListener lets JSON-RPC stream pending transaction hashes.
func (app *App) RegisterPendingTxListener(listener func(common.Hash)) {
	app.pendingTxListeners = append(app.pendingTxListeners, listener)
}

func (app *App) setPostHandler() {
	postHandler, err := posthandler.NewPostHandler(posthandler.HandlerOptions{})
	if err != nil {
		panic(err)
	}
	app.SetPostHandler(postHandler)
}

func (app *App) Name() string { return app.BaseApp.Name() }

func (app *App) BeginBlocker(ctx sdk.Context) (sdk.BeginBlock, error) {
	return app.ModuleManager.BeginBlock(ctx)
}

func (app *App) EndBlocker(ctx sdk.Context) (sdk.EndBlock, error) {
	return app.ModuleManager.EndBlock(ctx)
}

func (app *App) FinalizeBlock(req *abci.RequestFinalizeBlock) (*abci.ResponseFinalizeBlock, error) {
	return app.BaseApp.FinalizeBlock(req)
}

func (app *App) Configurator() module.Configurator {
	return app.configurator
}

func (app *App) InitChainer(ctx sdk.Context, req *abci.RequestInitChain) (*abci.ResponseInitChain, error) {
	var genesisState GenesisState
	if err := json.Unmarshal(req.AppStateBytes, &genesisState); err != nil {
		panic(err)
	}

	if err := app.UpgradeKeeper.SetModuleVersionMap(ctx, app.ModuleManager.GetVersionMap()); err != nil {
		panic(err)
	}

	return app.ModuleManager.InitGenesis(ctx, app.appCodec, genesisState)
}

func (app *App) PreBlocker(ctx sdk.Context, _ *abci.RequestFinalizeBlock) (*sdk.ResponsePreBlock, error) {
	return app.ModuleManager.PreBlock(ctx)
}

func (app *App) LoadHeight(height int64) error {
	return app.LoadVersion(height)
}

func (app *App) LegacyAmino() *codec.LegacyAmino {
	return app.legacyAmino
}

func (app *App) AppCodec() codec.Codec {
	return app.appCodec
}

func (app *App) InterfaceRegistry() codectypes.InterfaceRegistry {
	return app.interfaceRegistry
}

func (app *App) TxConfig() client.TxConfig {
	return app.txConfig
}

func (app *App) GetKey(storeKey string) *storetypes.KVStoreKey {
	return app.keys[storeKey]
}

func (app *App) SimulationManager() *module.SimulationManager {
	return app.sm
}

func (app *App) RegisterAPIRoutes(apiSvr *api.Server, apiConfig serverconfig.APIConfig) {
	clientCtx := apiSvr.ClientCtx
	authtx.RegisterGRPCGatewayRoutes(clientCtx, apiSvr.GRPCGatewayRouter)
	cmtservice.RegisterGRPCGatewayRoutes(clientCtx, apiSvr.GRPCGatewayRouter)
	node.RegisterGRPCGatewayRoutes(clientCtx, apiSvr.GRPCGatewayRouter)
	app.BasicModuleManager.RegisterGRPCGatewayRoutes(clientCtx, apiSvr.GRPCGatewayRouter)

	if err := sdkserver.RegisterSwaggerAPI(apiSvr.ClientCtx, apiSvr.Router, apiConfig.Swagger); err != nil {
		panic(err)
	}

	docs.RegisterOpenAPIService(Name, apiSvr.Router)
}

func (app *App) RegisterTxService(clientCtx client.Context) {
	authtx.RegisterTxService(app.GRPCQueryRouter(), clientCtx, app.Simulate, app.interfaceRegistry)
}

func (app *App) RegisterTendermintService(clientCtx client.Context) {
	cmtservice.RegisterTendermintService(clientCtx, app.GRPCQueryRouter(), app.interfaceRegistry, app.Query)
}

func (app *App) RegisterNodeService(clientCtx client.Context, cfg serverconfig.Config) {
	node.RegisterNodeService(clientCtx, app.GRPCQueryRouter(), cfg, func() int64 {
		return app.CommitMultiStore().EarliestVersion()
	})
}

func (app *App) GetMempool() sdkmempool.ExtMempool {
	return app.EVMMempool
}

func (app *App) GetAnteHandler() sdk.AnteHandler {
	return app.AnteHandler()
}

func (app *App) Close() error {
	var err error
	if mempool, ok := app.EVMMempool.(*evmmempool.Mempool); ok && mempool != nil {
		app.Logger().Info("shutting down EVM mempool")
		err = mempool.Close()
	}

	err = errors.Join(err, app.BaseApp.Close())
	if err == nil {
		app.Logger().Info("application gracefully shutdown")
	} else {
		app.Logger().Error("application shutdown completed with errors", "error", err)
	}

	return err
}

func (app *App) DefaultNodeHome() string {
	return DefaultNodeHome
}

func defaultEVMChainID(appOpts servertypes.AppOptions) uint64 {
	evmChainID := cast.ToUint64(appOpts.Get(srvflags.EVMChainID))
	if evmChainID == 0 {
		return DefaultEVMChainID
	}
	return evmChainID
}

func kudoraBaseDenomGetter(app *App) func(storetypes.MultiStore) string {
	return func(ms storetypes.MultiStore) string {
		return app.EVMKeeper.GetParams(sdk.NewContext(ms, cmtproto.Header{}, false, log.NewNopLogger())).EvmDenom
	}
}

func setupPowerReduction() {
	sdk.DefaultPowerReduction = evmutils.AttoPowerReduction
}
