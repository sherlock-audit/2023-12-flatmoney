// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import "forge-std/console2.sol";
import {FFIScripts} from "./FFIScripts.sol";

abstract contract ExpectRevert is Test, FFIScripts {
    using stdJson for string;

    string constant JSON_ERROR_SELECTOR_MAPPING = "/scripts/misc/errorSelectorMap.json";

    function _expectRevertWith(address target, bytes memory callData, string memory revertMessage) internal {
        (bool success, bytes memory returnData) = target.call(callData);

        string memory returnDataString = _decodeRevertReason(returnData);
        bytes32 hashedReturnDataString = keccak256(abi.encodePacked(returnDataString));

        if (success) {
            revert("Expected revert but got success");
        } else {
            if (hashedReturnDataString == keccak256(abi.encodePacked("Transaction reverted silently"))) {
                if (bytes(revertMessage).length > 0) {
                    revert(string.concat("Transaction reverted silently but expected ", revertMessage));
                }
            } else if (hashedReturnDataString != keccak256(abi.encodePacked(revertMessage))) {
                revert(string.concat("Reverted with wrong reason: ", returnDataString));
            }
        }
    }

    /// @dev Use this function if expecting a revert due to custom error.
    function _expectRevertWithCustomError(address target, bytes memory callData, bytes memory errorData) internal {
        _expectRevertWithCustomError(target, callData, errorData, 0);
    }

    function _expectRevertWithCustomError(
        address target,
        bytes memory callData,
        bytes memory errorData,
        uint256 value
    ) internal {
        (bool success, bytes memory returnData) = target.call{value: value}(callData);

        if (success) {
            revert("Expected revert but got success");
        } else {
            if (returnData.length == 0) {
                revert("Expected revert with custom error but got revert without reason");
            } else {
                if (keccak256(returnData) != keccak256(errorData)) {
                    bytes4 errorSelector;

                    assembly {
                        errorSelector := mload(add(returnData, 0x20))
                    }

                    revert(
                        string.concat(
                            "Expected revert with custom error but got revert with error selector: ",
                            _getErrorNameFromSelector(errorSelector)
                        )
                    );
                }
            }
        }
    }

    /// @dev This function can be used when expecting a revert with a custom error selector.
    /// @param target The target contract to call.
    /// @param callData The call data to use.
    /// @param errorData The error selector to expect.
    /// @param ignoreErrorArguments Whether to ignore the returned error arguments or not.
    function _expectRevertWithCustomError(
        address target,
        bytes memory callData,
        bytes4 errorData,
        bool ignoreErrorArguments
    ) internal {
        _expectRevertWithCustomError(target, callData, errorData, ignoreErrorArguments, 0);
    }

    /// @dev Payable call with value
    function _expectRevertWithCustomError(
        address target,
        bytes memory callData,
        bytes4 errorData,
        bool ignoreErrorArguments,
        uint256 value
    ) internal {
        (bool success, bytes memory returnData) = target.call{value: value}(callData);

        if (success) {
            revert("Expected revert but got success");
        } else {
            if (returnData.length == 0) {
                revert("Expected revert with custom error but got revert without reason");
            } else {
                if (returnData.length == 4) {
                    if (bytes4(returnData) != errorData) {
                        string memory errorName = _getErrorNameFromSelector(bytes4(returnData));
                        revert(
                            string.concat(
                                "Expected revert with custom error but got revert with error selector: ",
                                errorName
                            )
                        );
                    }
                } else if (ignoreErrorArguments) {
                    bytes4 errorSelector;

                    assembly {
                        errorSelector := mload(add(returnData, 0x20))
                    }

                    if (errorSelector != errorData) {
                        string memory errorName = _getErrorNameFromSelector(errorSelector);
                        revert(
                            string.concat(
                                "Expected revert with custom error but got revert with error selector: ",
                                errorName
                            )
                        );
                    }
                } else {
                    revert("Expected revert with only custom error selector but got the error arguments as well");
                }
            }
        }
    }

    function _decodeRevertReason(bytes memory data) internal pure returns (string memory) {
        // If the _res length is less than 68, then the transaction failed silently (without a revert message)
        if (data.length < 68) return "Transaction reverted silently";

        assembly {
            // Slice the sighash.
            data := add(data, 0x04)
        }

        return abi.decode(data, (string)); // All that remains is the revert string
    }
}
