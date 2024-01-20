// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import "forge-std/console2.sol";

abstract contract ExpectRevert is Test {
    using stdJson for string;

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
    function _expectRevertWithCustomError(
        address target,
        bytes memory callData,
        string memory expectedErrorSignature,
        bytes memory errorData
    ) internal {
        _expectRevertWithCustomError(target, callData, expectedErrorSignature, errorData, 0);
    }

    function _expectRevertWithCustomError(
        address target,
        bytes memory callData,
        string memory expectedErrorSignature,
        bytes memory errorData,
        uint256 value
    ) internal {
        bytes4 expectedErrorSelector = bytes4(keccak256(abi.encodePacked(expectedErrorSignature)));
        bytes4 encodedErrorSelector;

        assembly {
            encodedErrorSelector := mload(add(errorData, 0x20))
        }

        // If the expected error selector and the encoded error selector are different,
        // then maybe the expected error data encoding is done incorrectly (using some other error's encoding).
        if (encodedErrorSelector != expectedErrorSelector) {
            revert(
                string.concat(
                    "Expected error selector doesn't match the encoded error data's selector:",
                    "\nExpected: ",
                    vm.toString(expectedErrorSelector),
                    "\nGot: ",
                    vm.toString(encodedErrorSelector)
                )
            );
        }

        (bool success, bytes memory returnData) = target.call{value: value}(callData);

        if (success) {
            revert(string.concat("Expected revert due to ", expectedErrorSignature, " but got success"));
        } else {
            if (returnData.length == 0) {
                revert(
                    string.concat("Expected revert due to ", expectedErrorSignature, " but got revert without reason")
                );
            } else {
                bytes4 errorSelector;

                assembly {
                    errorSelector := mload(add(returnData, 0x20))
                }

                // If the return data doesn't match the error data that we expected:
                //    - Check if the error selectors are the same. This means that the expected error data is wrong.
                //    - If the error selectors are differen, then the entire expected test has failed.
                if (keccak256(returnData) != keccak256(errorData)) {
                    // If the error selector is itself different, then the entire test has failed.
                    if (errorSelector != expectedErrorSelector) {
                        revert(
                            string.concat(
                                "Expected revert due to ",
                                expectedErrorSignature,
                                " but reverted due to selector: ",
                                vm.toString(bytes4(errorSelector))
                            )
                        );
                    } else {
                        // If the expected, encoded and returned error selectors are the same,
                        // then the expected error data is wrong so revert with that reason.
                        revert(
                            string.concat(
                                "Expected error signature correct but the error data is wrong:",
                                "\nExpected: ",
                                vm.toString(errorData),
                                "\nGot: ",
                                vm.toString(returnData)
                            )
                        );
                    }
                }
            }
        }
    }

    /// @dev This function can be used when expecting a revert with a custom error selector.
    /// @param target The target contract to call.
    /// @param callData The call data to use.
    /// @param expectedErrorSignature The error signature to expect.
    /// @param ignoreErrorArguments Whether to ignore the returned error arguments or not.
    function _expectRevertWithCustomError(
        address target,
        bytes memory callData,
        string memory expectedErrorSignature,
        bool ignoreErrorArguments
    ) internal {
        _expectRevertWithCustomError(target, callData, expectedErrorSignature, ignoreErrorArguments, 0);
    }

    /// @dev Payable call with value
    function _expectRevertWithCustomError(
        address target,
        bytes memory callData,
        string memory expectedErrorSignature,
        bool ignoreErrorArguments,
        uint256 value
    ) internal {
        bytes4 expectedErrorSelector = bytes4(keccak256(abi.encodePacked(expectedErrorSignature)));

        (bool success, bytes memory returnData) = target.call{value: value}(callData);

        if (success) {
            revert(string.concat("Expected revert due to ", expectedErrorSignature, " but got success"));
        } else {
            if (returnData.length == 0) {
                revert(
                    string.concat("Expected revert due to ", expectedErrorSignature, " but got revert without reason")
                );
            } else {
                if (returnData.length == 4) {
                    if (bytes4(returnData) != expectedErrorSelector) {
                        revert(
                            string.concat(
                                "Expected revert due to ",
                                expectedErrorSignature,
                                " but got revert due to selector: ",
                                vm.toString(returnData)
                            )
                        );
                    }
                } else if (ignoreErrorArguments) {
                    bytes4 errorSelector;

                    assembly {
                        errorSelector := mload(add(returnData, 0x20))
                    }

                    if (errorSelector != expectedErrorSelector) {
                        revert(
                            string.concat(
                                "Expected revert due to ",
                                expectedErrorSignature,
                                " but got revert due to selector: ",
                                vm.toString(errorSelector)
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
