//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "openzeppelin/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import "../src/preLaunch/WadingPool.sol";

contract TestWadingPool is Test {
    ERC20PresetFixedSupply public pnsh;
    ERC20PresetFixedSupply public nsh;
    WadingPool public wadingPool;

    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");
    address user4 = makeAddr("user4");

    function setUp() public {
        pnsh = new ERC20PresetFixedSupply(
            "pNSH",
            "pNSH",
            1_000_000 ether,
            address(this)
        );
        nsh = new ERC20PresetFixedSupply(
            "NSH",
            "NSH",
            1_000_000 ether,
            address(this)
        );
        wadingPool = new WadingPool(address(pnsh));

        pnsh.approve(address(wadingPool), 1_000_000 ether);
        pnsh.transfer(user1, 1000 ether);
        pnsh.transfer(user2, 1000 ether);
        pnsh.transfer(user3, 1000 ether);
        pnsh.transfer(user4, 1000 ether);
        vm.prank(user1);
        pnsh.approve(address(wadingPool), 1000 ether);
        vm.prank(user2);
        pnsh.approve(address(wadingPool), 1000 ether);
        vm.prank(user3);
        pnsh.approve(address(wadingPool), 1000 ether);
        vm.prank(user4);
        pnsh.approve(address(wadingPool), 1000 ether);
    }

    function test_setNSH() public {
        wadingPool.setNSH(address(nsh));
        assertEq(address(wadingPool.nsh()), address(nsh));
    }

    function test_depositPNSH() public {
        vm.prank(user1);
        wadingPool.deposit(100 ether);
        assertEq(wadingPool.totalStaked(), 100 ether);
        (
            uint amount,
            uint offsetPoints,
            uint lockedAmount,
            bool claimed
        ) = wadingPool.userDeposits(user1);
        assertEq(amount, 100 ether);
        assertEq(offsetPoints, 0);
        assertEq(lockedAmount, 0);
        assertEq(claimed, false);

        assertEq(pnsh.balanceOf(address(wadingPool)), 100 ether);
    }

    function test_rewardDistribution() public {
        vm.prank(user1);
        wadingPool.deposit(100 ether);
        vm.prank(user2);
        wadingPool.deposit(100 ether);
        vm.prank(user3);
        wadingPool.deposit(200 ether);
        vm.prank(user4);
        wadingPool.deposit(400 ether);

        wadingPool.addRewards(1000 ether);

        assertEq(
            wadingPool.accumulatedRewardsPerToken(),
            (1000 ether * 1e18) / 800 ether
        );
        assertEq(pnsh.balanceOf(address(wadingPool)), 1800 ether);
    }

    function test_claim() public {
        vm.prank(user1);
        wadingPool.deposit(100 ether);
        vm.prank(user2);
        wadingPool.deposit(100 ether);
        vm.prank(user3);
        wadingPool.deposit(100 ether);
        vm.prank(user4);
        wadingPool.deposit(100 ether);

        wadingPool.addRewards(1000 ether);

        vm.expectRevert();
        vm.prank(user1);
        wadingPool.claim();

        nsh.transfer(address(wadingPool), 1400 ether);
        wadingPool.setNSH(address(nsh));

        vm.prank(user1);
        wadingPool.claim();

        assertEq(nsh.balanceOf(user1), 350 ether);
        (, , , bool claimed) = wadingPool.userDeposits(user1);
        assertEq(claimed, true);
    }
}
