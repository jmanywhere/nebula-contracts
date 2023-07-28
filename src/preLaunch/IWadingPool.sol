// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IWadingPool {
    /**
     * @dev Add rewards to the pool
     * @param amount Amount of rewards to add
     */
    function addRewards(uint amount) external;
}
