// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.19;

import "openzeppelin/access/AccessControlEnumerable.sol";
import "openzeppelin/token/ERC20/IERC20.sol";

/**
 * @title Whitelist
 * @dev The Whitelist contract has a whitelist of addresses, and provides basic authorization control functions.
 * @dev This simplifies the implementation of "user permissions".
 */
contract Whitelist is AccessControlEnumerable {
    bytes32 public constant WHITELIST_ROLE = keccak256("WHITELIST_ROLE");
    mapping(address => bool) public whitelist;

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /**
     * @dev Throws if called by any account that's not whitelisted.
     */
    modifier onlyWhitelisted() {
        require(
            hasRole(WHITELIST_ROLE, msg.sender),
            "Whitelist: Not whitelisted"
        );
        _;
    }

    function addAddressesToWhitelist(
        address[] memory addrs
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < addrs.length; i++) {
            _grantRole(WHITELIST_ROLE, addrs[i]);
        }
    }

    function removeAddressesFromWhitelist(
        address[] memory addrs
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < addrs.length; i++) {
            _revokeRole(WHITELIST_ROLE, addrs[i]);
        }
    }

    function recoverERC20(
        address tokenAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(tokenAddress).transfer(
            _msgSender(),
            IERC20(tokenAddress).balanceOf(address(this))
        );
    }
}
