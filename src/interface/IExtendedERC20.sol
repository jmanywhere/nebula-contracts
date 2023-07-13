// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin/token/ERC20/IERC20.sol";

interface IExtendedERC20 is IERC20 {
    function mint(address to, uint amount) external;

    function burn(uint amount) external;

    function burnFrom(address from, uint amount) external;
}
