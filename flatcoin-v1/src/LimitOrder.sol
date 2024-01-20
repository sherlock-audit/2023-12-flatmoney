// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";

import {FlatcoinStructs} from "./libraries/FlatcoinStructs.sol";
import {FlatcoinErrors} from "./libraries/FlatcoinErrors.sol";
import {FlatcoinModuleKeys} from "./libraries/FlatcoinModuleKeys.sol";
import {FlatcoinEvents} from "./libraries/FlatcoinEvents.sol";
import {ModuleUpgradeable} from "./abstracts/ModuleUpgradeable.sol";
import {OracleModifiers} from "./abstracts/OracleModifiers.sol";
import {InvariantChecks} from "./misc/InvariantChecks.sol";

import {ILimitOrder} from "./interfaces/ILimitOrder.sol";
import {IFlatcoinVault} from "./interfaces/IFlatcoinVault.sol";
import {ILeverageModule} from "./interfaces/ILeverageModule.sol";
import {IStableModule} from "./interfaces/IStableModule.sol";
import {IOracleModule} from "./interfaces/IOracleModule.sol";
import {IKeeperFee} from "./interfaces/IKeeperFee.sol";

/// @title LimitOrder
/// @author dHEDGE
/// @notice Module to create limit orders.
contract LimitOrder is ILimitOrder, ModuleUpgradeable, ReentrancyGuardUpgradeable, InvariantChecks, OracleModifiers {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeERC20Upgradeable for IStableModule;
    using SignedMath for int256;

    /// @dev To prevent the implementation contract from being used, we invoke the _disableInitializers
    /// function in the constructor to automatically lock it when it is deployed.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    mapping(uint256 tokenId => FlatcoinStructs.Order order) internal _limitOrderClose;

    /// @notice Function to initialize this contract.
    function initialize(IFlatcoinVault _vault) external initializer {
        __Module_init(FlatcoinModuleKeys._LIMIT_ORDER_KEY, _vault);
        __ReentrancyGuard_init();
    }

    /////////////////////////////////////////////
    //         Trader Write Functions          //
    /////////////////////////////////////////////

    /// @notice Announces a limit order to close a position
    /// @param tokenId The position to close
    /// @param priceLowerThreshold The stop-loss price
    /// @param priceUpperThreshold The profit-take price
    /// @dev Currently can only be used for closing existing orders
    ///      The keeper fee will be determined at execution time, and the trader takes this risk.
    ///      This is because there could be a large time difference between limit order announcement and execution.
    function announceLimitOrder(uint256 tokenId, uint256 priceLowerThreshold, uint256 priceUpperThreshold) external {
        uint64 executableAtTime = _prepareAnnouncementOrder();
        address positionOwner = _checkPositionOwner(tokenId);
        _checkThresholds(priceLowerThreshold, priceUpperThreshold);
        uint256 tradeFee = ILeverageModule(vault.moduleAddress(FlatcoinModuleKeys._LEVERAGE_MODULE_KEY)).getTradeFee(
            vault.getPosition(tokenId).additionalSize
        );

        _limitOrderClose[tokenId] = FlatcoinStructs.Order({
            orderType: FlatcoinStructs.OrderType.LimitClose,
            orderData: abi.encode(
                FlatcoinStructs.LimitClose(tokenId, priceLowerThreshold, priceUpperThreshold, tradeFee)
            ),
            keeperFee: 0, // Not applicable for limit orders. Keeper fee will be determined at execution time.
            executableAtTime: executableAtTime
        });

        // Lock the NFT belonging to this position so that it can't be transferred to someone else.
        ILeverageModule(vault.moduleAddress(FlatcoinModuleKeys._LEVERAGE_MODULE_KEY)).lock(tokenId);

        emit FlatcoinEvents.OrderAnnounced({
            account: positionOwner,
            orderType: FlatcoinStructs.OrderType.LimitClose,
            keeperFee: 0
        });
    }

    /// @notice Cancels a limit order
    /// @param tokenId The position to close
    function cancelLimitOrder(uint256 tokenId) external {
        address positionOwner = _checkPositionOwner(tokenId);
        _checkLimitCloseOrder(tokenId);

        delete _limitOrderClose[tokenId];

        // Unlock the ERC721 position NFT to allow for transfers.
        ILeverageModule(vault.moduleAddress(FlatcoinModuleKeys._LEVERAGE_MODULE_KEY)).unlock(tokenId);

        emit FlatcoinEvents.OrderCancelled({account: positionOwner, orderType: FlatcoinStructs.OrderType.LimitClose});
    }

    /// @notice Cancel limit order called by other modules
    /// @dev Used by the LeverageModule to cancel any existing limit order when the position is closed.
    function cancelExistingLimitOrder(uint256 tokenId) external onlyAuthorizedModule returns (bool cancelled) {
        if (_limitOrderClose[tokenId].orderType == FlatcoinStructs.OrderType.LimitClose) {
            delete _limitOrderClose[tokenId];

            cancelled = true;

            // Unlock the ERC721 position NFT to allow for transfers.
            ILeverageModule(vault.moduleAddress(FlatcoinModuleKeys._LEVERAGE_MODULE_KEY)).unlock(tokenId);

            emit FlatcoinEvents.OrderCancelled({
                account: ILeverageModule(vault.moduleAddress(FlatcoinModuleKeys._LEVERAGE_MODULE_KEY)).ownerOf(tokenId),
                orderType: FlatcoinStructs.OrderType.LimitClose
            });
        }
    }

    /// @notice Function to execute a limit order
    /// @dev This function is typically called by the keeper
    function executeLimitOrder(
        uint256 tokenId,
        bytes[] calldata priceUpdateData
    ) external payable nonReentrant updatePythPrice(vault, msg.sender, priceUpdateData) orderInvariantChecks(vault) {
        _checkLimitCloseOrder(tokenId);

        vault.settleFundingFees();

        _closePosition(tokenId);
    }

    /////////////////////////////////////////////
    //           Internal Functions            //
    /////////////////////////////////////////////

    function _closePosition(uint256 tokenId) internal {
        ILeverageModule leverageModule = ILeverageModule(vault.moduleAddress(FlatcoinModuleKeys._LEVERAGE_MODULE_KEY));
        FlatcoinStructs.Order memory order = _limitOrderClose[tokenId];
        FlatcoinStructs.LimitClose memory _limitOrder = abi.decode(
            _limitOrderClose[tokenId].orderData,
            (FlatcoinStructs.LimitClose)
        );
        address account = leverageModule.ownerOf(tokenId);

        (uint256 price, ) = IOracleModule(vault.moduleAddress(FlatcoinModuleKeys._ORACLE_MODULE_KEY)).getPrice();

        // Check that the minimum time delay is reached before execution
        if (block.timestamp < order.executableAtTime)
            revert FlatcoinErrors.ExecutableTimeNotReached(order.executableAtTime);

        uint256 minFillPrice;

        if (price <= _limitOrder.priceLowerThreshold) {
            minFillPrice = 0; // can execute below lower limit price threshold
        } else if (price >= _limitOrder.priceUpperThreshold) {
            minFillPrice = _limitOrder.priceUpperThreshold;
        } else {
            revert FlatcoinErrors.LimitOrderPriceNotInRange(
                price,
                _limitOrder.priceLowerThreshold,
                _limitOrder.priceUpperThreshold
            );
        }

        // Delete the order tracker from storage.
        delete _limitOrderClose[tokenId];

        order.orderData = abi.encode(
            FlatcoinStructs.AnnouncedLeverageClose({
                tokenId: tokenId,
                minFillPrice: minFillPrice,
                tradeFee: _limitOrder.tradeFee
            })
        );
        order.keeperFee = IKeeperFee(vault.moduleAddress(FlatcoinModuleKeys._KEEPER_FEE_MODULE_KEY)).getKeeperFee();
        leverageModule.executeClose({account: account, keeper: msg.sender, order: order});

        emit FlatcoinEvents.OrderExecuted({account: account, orderType: order.orderType, keeperFee: order.keeperFee});
    }

    function _checkPositionOwner(uint256 tokenId) internal view returns (address positionOwner) {
        positionOwner = ILeverageModule(vault.moduleAddress(FlatcoinModuleKeys._LEVERAGE_MODULE_KEY)).ownerOf(tokenId);

        if (positionOwner != msg.sender) revert FlatcoinErrors.NotTokenOwner(tokenId, msg.sender);
    }

    function _checkThresholds(uint256 priceLowerThreshold, uint256 priceUpperThreshold) internal pure {
        if (priceLowerThreshold >= priceUpperThreshold)
            revert FlatcoinErrors.InvalidThresholds(priceLowerThreshold, priceUpperThreshold);
    }

    function _checkLimitCloseOrder(uint256 tokenId) internal view {
        FlatcoinStructs.Order memory _limitOrder = _limitOrderClose[tokenId];

        if (_limitOrder.orderType != FlatcoinStructs.OrderType.LimitClose)
            revert FlatcoinErrors.LimitOrderInvalid(tokenId);
    }

    /// @dev This function HAS to be called as soon as the transaction flow enters an announce function.
    function _prepareAnnouncementOrder() internal returns (uint64 executableAtTime) {
        // Settle funding fees to not encounter the `MaxSkewReached` error.
        // This error could happen if the funding fees are not settled for a long time and the market is skewed long
        // for a long time.
        vault.settleFundingFees();

        executableAtTime = uint64(block.timestamp + vault.minExecutabilityAge());
    }

    /////////////////////////////////////////////
    //              View Functions             //
    /////////////////////////////////////////////

    function getLimitOrder(uint256 tokenId) external view returns (FlatcoinStructs.Order memory order) {
        return _limitOrderClose[tokenId];
    }
}
