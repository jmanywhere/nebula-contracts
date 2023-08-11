// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/access/Ownable.sol";
import "./IWadingPool.sol";

error WadingPool__Already_Claimed();
error WadingPool__Invalid_NSH();

contract WadingPool is Ownable, IWadingPool {
    struct UserDeposit {
        uint amount;
        uint offsetPoints;
        uint lockedAmount;
        bool claimed;
    }

    mapping(address => UserDeposit) public userDeposits;

    IERC20 public pnsh;
    IERC20 public nsh;
    uint public accumulatedRewardsPerToken;
    uint public totalStaked;
    uint public totalRewarded;
    uint private constant MAGNIFIER = 1e18;

    event RewardsAdded(uint amount);
    event ClaimNSH(address indexed user, uint amount);

    constructor(address _pNSH) {
        pnsh = IERC20(_pNSH);
    }

    function setNSH(address _nsh) external onlyOwner {
        nsh = IERC20(_nsh);
    }

    function addRewards(uint amount) external {
        totalRewarded += amount;
        accumulatedRewardsPerToken += (amount * MAGNIFIER) / totalStaked;
        pnsh.transferFrom(msg.sender, address(this), amount);
        emit RewardsAdded(amount);
    }

    function deposit(uint amount) external {
        UserDeposit storage userDeposit = userDeposits[msg.sender];
        if (userDeposit.claimed) revert WadingPool__Already_Claimed();
        _lockTokens(msg.sender);
        userDeposit.amount += amount;
        userDeposit.offsetPoints = amount * accumulatedRewardsPerToken;
        totalStaked += amount;
        pnsh.transferFrom(msg.sender, address(this), amount);
    }

    function claim() external {
        if (address(nsh) == address(0)) revert WadingPool__Invalid_NSH();
        UserDeposit storage userDeposit = userDeposits[msg.sender];
        if (userDeposit.claimed) revert WadingPool__Already_Claimed();
        _lockTokens(msg.sender);
        userDeposit.claimed = true;
        uint amount = userDeposit.amount + userDeposit.lockedAmount;

        nsh.transfer(msg.sender, amount);
        emit ClaimNSH(msg.sender, amount);
    }

    function _lockTokens(address _user) private {
        UserDeposit storage userDeposit = userDeposits[_user];
        if (userDeposit.amount == 0) return;
        uint totalTokens = userDeposit.amount * accumulatedRewardsPerToken;
        uint tokensToLock = (totalTokens - userDeposit.offsetPoints) /
            MAGNIFIER;
        userDeposit.lockedAmount += tokensToLock;
        userDeposit.offsetPoints = totalTokens;
    }
}
