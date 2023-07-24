//SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "forge-std/Test.sol";
// Contracts
import "../src/NSH.sol";

contract NSH_test is Test {
    NSH nsh;
    address minter = makeAddr("minter");
    address user1 = makeAddr("user1");
    bytes32 minterRole = keccak256("MINTER_ROLE");

    function setUp() public {
        nsh = new NSH();
    }

    function test_mint_specs() public {
        assertEq(nsh.totalSupply(), 1_500_000_000 ether);
        assertEq(nsh.MAX_SUPPLY(), 10_000_000_000 ether);
    }

    function test_set_minter() public {
        vm.expectRevert();
        vm.prank(minter);
        nsh.mint(user1, 100 ether);

        nsh.grantRole(minterRole, minter);

        vm.prank(minter);
        nsh.mint(user1, 100 ether);

        assertEq(nsh.balanceOf(user1), 100 ether);
    }
}
