// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";

abstract contract FFIScripts is Test {
    function _getErrorNameFromSelector(bytes4 selector) internal returns (string memory) {
        string[] memory inputs = new string[](3);

        inputs[0] = "node";
        inputs[1] = "scripts/test-helpers/get-error-name.js";
        inputs[2] = vm.toString(selector);

        Vm.FfiResult memory result = vm.tryFfi(inputs);

        if (result.exitCode != 0) {
            revert(string.concat("Error name lookup script failed: ", string(result.stderr)));
        }

        return string(result.stdout);
    }
}
