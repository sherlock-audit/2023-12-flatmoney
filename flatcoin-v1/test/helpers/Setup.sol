// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {ProxyAdmin} from "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Create2Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/Create2Upgradeable.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {MockPyth} from "pyth-sdk-solidity/MockPyth.sol";
import {IPyth} from "pyth-sdk-solidity/IPyth.sol";

import {DelayedOrder} from "src/DelayedOrder.sol";
import {FlatcoinVault} from "src/FlatcoinVault.sol";
import {LimitOrder} from "src/LimitOrder.sol";
import {StableModule} from "src/StableModule.sol";
import {OracleModule} from "src/OracleModule.sol";
import {LeverageModule} from "src/LeverageModule.sol";
import {PointsModule} from "src/PointsModule.sol";
import {MockKeeperFee} from "../unit/mocks/MockKeeperFee.sol";

import {FlatcoinStructs} from "src/libraries/FlatcoinStructs.sol";
import {FlatcoinModuleKeys} from "src/libraries/FlatcoinModuleKeys.sol";

import {IChainlinkAggregatorV3} from "src/interfaces/IChainlinkAggregatorV3.sol";
import {ILeverageModule} from "src/interfaces/ILeverageModule.sol";
import {IStableModule} from "src/interfaces/IStableModule.sol";
import {IPointsModule} from "src/interfaces/IPointsModule.sol";
import {IKeeperFee} from "src/interfaces/IKeeperFee.sol";

import {Viewer} from "src/misc/Viewer.sol";
import {LiquidationModule} from "src/LiquidationModule.sol";

import "forge-std/Test.sol";
import "forge-std/console2.sol";

abstract contract Setup is Test {
    /********************************************
     *                 Accounts                 *
     ********************************************/
    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal keeper = makeAddr("keeper");
    address internal liquidator = makeAddr("liquidator");
    address internal treasury = makeAddr("treasury");
    address[] internal accounts = [admin, alice, bob, carol, keeper, liquidator, treasury];

    /********************************************
     *                 Mocks                    *
     ********************************************/
    IChainlinkAggregatorV3 internal wethChainlinkAggregatorV3 =
        IChainlinkAggregatorV3(makeAddr("chainlinkAggregatorV3"));
    ERC20 internal WETH;
    MockPyth internal mockPyth; // validTimePeriod, singleUpdateFeeInWei
    IKeeperFee internal mockKeeperFee;

    /********************************************
     *             System contracts             *
     ********************************************/
    bytes32 internal constant STABLE_MODULE_KEY = FlatcoinModuleKeys._STABLE_MODULE_KEY;
    bytes32 internal constant LEVERAGE_MODULE_KEY = FlatcoinModuleKeys._LEVERAGE_MODULE_KEY;
    bytes32 internal constant ORACLE_MODULE_KEY = FlatcoinModuleKeys._ORACLE_MODULE_KEY;
    bytes32 internal constant DELAYED_ORDER_KEY = FlatcoinModuleKeys._DELAYED_ORDER_KEY;
    bytes32 internal constant LIMIT_ORDER_KEY = FlatcoinModuleKeys._LIMIT_ORDER_KEY;
    bytes32 internal constant LIQUIDATION_MODULE_KEY = FlatcoinModuleKeys._LIQUIDATION_MODULE_KEY;
    bytes32 internal constant POINTS_MODULE_KEY = FlatcoinModuleKeys._POINTS_MODULE_KEY;
    bytes32 internal constant KEEPER_FEE_MODULE_KEY = FlatcoinModuleKeys._KEEPER_FEE_MODULE_KEY;

    address internal leverageModImplementation;
    address internal stableModImplementation;
    address internal oracleModImplementation;
    address internal delayedOrderImplementation;
    address internal limitOrderImplementation;
    address internal liquidationModImplementation;
    address internal pointsModImplementation;
    address internal vaultImplementation;

    ProxyAdmin internal proxyAdmin;
    LeverageModule internal leverageModProxy;
    StableModule internal stableModProxy;
    OracleModule internal oracleModProxy;
    DelayedOrder internal delayedOrderProxy;
    LimitOrder internal limitOrderProxy;
    LiquidationModule internal liquidationModProxy;
    PointsModule internal pointsModProxy;
    FlatcoinVault internal vaultProxy;
    Viewer internal viewer;

    function setUp() public virtual {
        vm.startPrank(admin);

        WETH = new ERC20("WETH Mock", "WETH");
        mockPyth = new MockPyth(60, 1);
        mockKeeperFee = new MockKeeperFee();

        // Deploy proxy admin for all the system contracts.
        proxyAdmin = new ProxyAdmin();

        // Deploy implementations of all the system contracts.
        leverageModImplementation = address(new LeverageModule());
        stableModImplementation = address(new StableModule());
        oracleModImplementation = address(new OracleModule());
        delayedOrderImplementation = address(new DelayedOrder());
        limitOrderImplementation = address(new LimitOrder());
        liquidationModImplementation = address(new LiquidationModule());
        pointsModImplementation = address(new PointsModule());
        vaultImplementation = address(new FlatcoinVault());

        // Deploy proxies using the above implementation contracts.
        leverageModProxy = LeverageModule(
            address(new TransparentUpgradeableProxy(leverageModImplementation, address(proxyAdmin), ""))
        );
        stableModProxy = StableModule(
            address(new TransparentUpgradeableProxy(stableModImplementation, address(proxyAdmin), ""))
        );
        oracleModProxy = OracleModule(
            address(new TransparentUpgradeableProxy(oracleModImplementation, address(proxyAdmin), ""))
        );
        delayedOrderProxy = DelayedOrder(
            address(new TransparentUpgradeableProxy(delayedOrderImplementation, address(proxyAdmin), ""))
        );
        limitOrderProxy = LimitOrder(
            address(new TransparentUpgradeableProxy(limitOrderImplementation, address(proxyAdmin), ""))
        );
        liquidationModProxy = LiquidationModule(
            address(new TransparentUpgradeableProxy(liquidationModImplementation, address(proxyAdmin), ""))
        );
        pointsModProxy = PointsModule(
            address(new TransparentUpgradeableProxy(pointsModImplementation, address(proxyAdmin), ""))
        );
        vaultProxy = FlatcoinVault(
            address(new TransparentUpgradeableProxy(vaultImplementation, address(proxyAdmin), ""))
        );

        // Initialize the vault.
        // By default, max funding velocity will be 0.
        vaultProxy.initialize({
            _owner: admin,
            _collateral: IERC20Upgradeable(address(WETH)),
            _maxFundingVelocity: 0,
            _maxVelocitySkew: 0.1e18, // 10% skew to reach max funding velocity
            _skewFractionMax: 1.2e18,
            _stableCollateralCap: type(uint256).max,
            _minExecutabilityAge: 10 seconds,
            _maxExecutabilityAge: 1 minutes
        });

        /* Initialize the modules */

        // Can consider later enabling trade fees for all tests. Eg set it to 0.1% 0.001e18
        leverageModProxy.initialize({
            _vault: vaultProxy,
            _levTradingFee: 0,
            _marginMin: 0.05e18,
            _leverageMin: 1.5e18,
            _leverageMax: 25e18
        });

        // Can consider later enabling trade fees for all tests. Eg set it to 0.5% 0.005e18
        stableModProxy.initialize({_vault: vaultProxy, _stableWithdrawFee: 0}); // 10 seconds minimum delay time before execution

        {
            FlatcoinStructs.OnchainOracle memory onchainOracle = FlatcoinStructs.OnchainOracle(
                wethChainlinkAggregatorV3,
                25 * 60 * 60 // // 25 hours for Chainlink oracle price to become stale
            );
            FlatcoinStructs.OffchainOracle memory offchainOracle = FlatcoinStructs.OffchainOracle(
                IPyth(address(mockPyth)),
                0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace,
                60, // max age of 60 seconds
                1000
            );
            oracleModProxy.initialize({
                _vault: vaultProxy,
                _asset: address(WETH),
                _onchainOracle: onchainOracle,
                _offchainOracle: offchainOracle,
                _maxDiffPercent: 1e18 // disable the price difference check for easier testing
            });
        }

        delayedOrderProxy.initialize({_vault: vaultProxy});

        limitOrderProxy.initialize({_vault: vaultProxy});

        liquidationModProxy.initialize({
            _vault: vaultProxy,
            _liquidationFeeRatio: 0.005e18, // 0.5% liquidation fee
            _liquidationBufferRatio: 0.005e18, // 0.5% liquidation buffer
            _liquidationFeeLowerBound: 4e18, // 4 USD
            _liquidationFeeUpperBound: 100e18 // 100 USD
        });

        pointsModProxy.initialize({
            _flatcoinVault: vaultProxy,
            _treasury: treasury,
            _unlockTaxVest: 365 days,
            _pointsPerSize: 200e18,
            _pointsPerDeposit: 100e18
        });

        {
            FlatcoinStructs.AuthorizedModule[] memory authorizedModules = new FlatcoinStructs.AuthorizedModule[](8);

            authorizedModules[0] = FlatcoinStructs.AuthorizedModule({
                moduleKey: STABLE_MODULE_KEY,
                moduleAddress: address(stableModProxy)
            });
            authorizedModules[1] = FlatcoinStructs.AuthorizedModule({
                moduleKey: LEVERAGE_MODULE_KEY,
                moduleAddress: address(leverageModProxy)
            });
            authorizedModules[2] = FlatcoinStructs.AuthorizedModule({
                moduleKey: ORACLE_MODULE_KEY,
                moduleAddress: address(oracleModProxy)
            });
            authorizedModules[3] = FlatcoinStructs.AuthorizedModule({
                moduleKey: DELAYED_ORDER_KEY,
                moduleAddress: address(delayedOrderProxy)
            });
            authorizedModules[4] = FlatcoinStructs.AuthorizedModule({
                moduleKey: LIMIT_ORDER_KEY,
                moduleAddress: address(limitOrderProxy)
            });
            authorizedModules[5] = FlatcoinStructs.AuthorizedModule({
                moduleKey: LIQUIDATION_MODULE_KEY,
                moduleAddress: address(liquidationModProxy)
            });
            authorizedModules[6] = FlatcoinStructs.AuthorizedModule({
                moduleKey: KEEPER_FEE_MODULE_KEY,
                moduleAddress: address(mockKeeperFee)
            });
            authorizedModules[7] = FlatcoinStructs.AuthorizedModule({
                moduleKey: POINTS_MODULE_KEY,
                moduleAddress: address(pointsModProxy)
            });

            // Authorize the modules within the vault.
            vaultProxy.addAuthorizedModules(authorizedModules);
        }

        // Deploy the viewer
        viewer = new Viewer(vaultProxy);

        _fillWallets(address(WETH));

        // Mock WETH Chainlink and Pyth network price to $1k
        setWethPrice(1000e8);

        vm.stopPrank();
    }

    /********************************************
     *             Helper Functions             *
     ********************************************/

    function _fillWallets(address token) internal {
        // Fill wallets of the dummy accounts.
        for (uint i = 0; i < accounts.length; ++i) {
            deal(token, accounts[i], 100_000e18); // Loading account with `token`.
            deal(accounts[i], 100_000e18); // Loading account with native token.
        }
    }

    function setWethPrice(uint256 price) public {
        skip(1); // Make sure the new price update for Pyth goes through. This requires a fresher timestamp than last update
        vm.mockCall(
            address(wethChainlinkAggregatorV3),
            abi.encodeWithSignature("latestRoundData()"),
            abi.encode(0, price, 0, block.timestamp, 0)
        );

        // Update Pyth network price
        bytes[] memory priceUpdateData = getPriceUpdateData(price);
        oracleModProxy.updatePythPrice{value: 1}(msg.sender, priceUpdateData);
    }

    function getPriceUpdateData(uint256 price) public view returns (bytes[] memory priceUpdateData) {
        // price = price / 1e10;

        priceUpdateData = new bytes[](1);
        priceUpdateData[0] = mockPyth.createPriceFeedUpdateData(
            0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace,
            int64(uint64(price)),
            uint64(price) / 10_000,
            -8,
            int64(uint64(price)),
            uint64(price) / 10_000,
            uint64(block.timestamp)
        );
    }
}
