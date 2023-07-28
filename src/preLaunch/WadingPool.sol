// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/access/Ownable.sol";
import "./IWadingPool.sol";

error WadingPool__Invalid_WithdrawDate();

contract WadingPool is Ownable, IWadingPool {
    IERC20 public pnsh;
    IERC20 public nsh;
    uint public withdrawDate;

    constructor(address _pNSH) {
        pnsh = IERC20(_pNSH);
    }

    function setNSH(address _nsh) external onlyOwner {
        nsh = IERC20(_nsh);
    }

    function setWithdrawDate(uint launchDate) external onlyOwner {
        if (withdrawDate <= block.timestamp + 10 days)
            revert WadingPool__Invalid_WithdrawDate();
        withdrawDate = launchDate;
    }

    function addRewards(uint amount) external {
        pnsh.transferFrom(msg.sender, address(this), amount);
    }
}
