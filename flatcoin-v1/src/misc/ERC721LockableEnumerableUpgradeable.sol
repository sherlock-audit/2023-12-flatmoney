// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {ERC721EnumerableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";

// solhint-disable reason-string
// solhint-disable custom-errors
contract ERC721LockableEnumerableUpgradeable is ERC721EnumerableUpgradeable {
    event Locked(uint256 indexed tokenId);
    event Unlocked(uint256 indexed tokenId);

    /// @notice Mapping which holds the lock status of each token ID.
    mapping(uint256 tokenId => bool lockStatus) internal _isLocked;

    // solhint-disable-next-line func-name-mixedcase
    function __ERC721LockableEnumerableUpgradeable_init()
        internal
        onlyInitializing // solhint-disable-next-line no-empty-blocks
    {}

    // solhint-disable-next-line func-name-mixedcase
    function __ERC721LockableEnumerableUpgradeable_init_unchained()
        internal
        onlyInitializing // solhint-disable-next-line no-empty-blocks
    {}

    /// @notice Function to lock a token ID.
    /// @dev Note that this function doesn't revert if the token ID is already locked.
    /// @dev Warning: This function doesn't check the caller is the owner of the token. That's why this should only be used by trusted modules.
    ///      which contain the check for the same.
    /// @param tokenId The ERC721 token ID to lock.
    function _lock(uint256 tokenId) internal virtual {
        _isLocked[tokenId] = true;

        emit Locked(tokenId);
    }

    /// @notice Function to unlock a token ID.
    /// @dev Note that this function doesn't revert if the token ID is already unlocked.
    /// @dev Warning: This function doesn't check the caller is the owner of the token. That's why this should only be used by trusted modules.
    ///      which contain the check for the same.
    /// @param tokenId The ERC721 token ID to unlock.
    function _unlock(uint256 tokenId) internal virtual {
        _isLocked[tokenId] = false;

        emit Unlocked(tokenId);
    }

    /// @notice Before token transfer hook.
    /// @dev Reverts if the token is locked. Make sure that when minting/burning a token it is unlocked.
    /// @param from The address to transfer tokens from.
    /// @param to The address to transfer tokens to.
    /// @param tokenId The ERC721 token ID to transfer.
    /// @param batchSize The number of tokens to transfer.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal virtual override {
        // Make sure the token is not locked.
        require(!_isLocked[tokenId], "ERC721LockableEnumerableUpgradeable: token is locked");

        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    uint256[49] private __gap;
}
