// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

//----------------------------------------------
// IMPORTS
//----------------------------------------------
import "openzeppelin/access/AccessControl.sol";
import "openzeppelin/token/ERC20/ERC20.sol";
import {IPeg} from "./interface/IBalancer.sol";

//-----------------------------------------------
// ERRORS
//-----------------------------------------------
error NUSD__Insufficient_Allowance();

contract NUSD is ERC20, AccessControl, IPeg {
    // Mint only by access and BURN can be turned ON or OFF but for everyone
    // Needs to have a mapping of LPs to check and add taxes to it.

    bytes32 private constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 private constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");

    PegState public currentEpochState;

    // Taxes on 3rd Party LPs like UniswapV2
    uint[] public buyTax = [0, 0, 0, 0, 5, 10];
    uint[] public sellTax = [10, 5, 0, 0, 0, 0];

    //-----------------------------------------------
    // Constructor
    //-----------------------------------------------
    constructor() ERC20("Nebula USD", "NUSD") {
        // Setup admin and fee manager roles
        grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        grantRole(FEE_MANAGER_ROLE, msg.sender);
    }

    //-----------------------------------------------
    // External Functions
    //-----------------------------------------------
    /**
     * Function to MINT tokens to a specified user.
     * @param _user Address to mint tokens to
     * @param _amount Amount of tokens to mint to
     * @dev this can only be called by the MINTER_ROLE
     */
    function mint(
        address _user,
        uint256 _amount
    ) external onlyRole(MINTER_ROLE) {
        _mint(_user, _amount);
    }

    /**
     * Burns tokens from the caller. We allow anyone to burn tokens
     * @param _amount Amount of tokens to BURN
     */
    function burn(uint _amount) external {
        _burn(msg.sender, _amount);
    }

    /**
     * Similar to transferFrom, but burns instead of transferring.
     * @param _user User to burn tokens from
     * @param _amount amount of tokens to BURN
     */
    function burnFrom(address _user, uint _amount) external {
        if (msg.sender != _user) {
            uint256 currentAllowance = allowance(_user, msg.sender);
            if (currentAllowance < _amount)
                revert NUSD__Insufficient_Allowance();
            _approve(_user, msg.sender, currentAllowance - _amount);
        }
        _burn(_user, _amount);
    }
}
