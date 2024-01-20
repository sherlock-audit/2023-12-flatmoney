// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

// solhint-disable reason-string
// solhint-disable custom-errors
contract ERC20LockableUpgradeable is Initializable, ERC20Upgradeable {
    event Locked(address indexed account, uint256 amount);
    event Unlocked(address indexed account, uint256 amount);

    mapping(address account => uint256 lockedAmount) internal _lockedAmount;

    // solhint-disable-next-line func-name-mixedcase
    function __ERC20LockableUpgradeable_init()
        internal
        onlyInitializing // solhint-disable-next-line no-empty-blocks
    {}

    // solhint-disable-next-line func-name-mixedcase
    function __ERC20LockableUpgradeable_init_unchained()
        internal
        onlyInitializing // solhint-disable-next-line no-empty-blocks
    {}

    function _lock(address account, uint256 amount) internal virtual {
        require(
            _lockedAmount[account] + amount <= balanceOf(account),
            "ERC20LockableUpgradeable: locked amount exceeds balance"
        );

        _lockedAmount[account] += amount;
        emit Locked(account, amount);
    }

    function _unlock(address account, uint256 amount) internal virtual {
        require(_lockedAmount[account] >= amount, "ERC20LockableUpgradeable: requested unlock exceeds locked balance");

        _lockedAmount[account] -= amount;

        emit Unlocked(account, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        // Make sure the sender has enough unlocked tokens.
        // Note: the below requirement is not needed when minting tokens in which case the `from` address is 0x0.
        if (from != address(0)) {
            require(
                balanceOf(from) - _lockedAmount[from] >= amount,
                "ERC20LockableUpgradeable: insufficient unlocked balance"
            );
        }

        super._beforeTokenTransfer(from, to, amount);
    }

    uint256[49] private __gap;
}
