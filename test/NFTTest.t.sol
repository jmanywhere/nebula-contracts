// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";

// Contracts under test
import "../src/NebuloidsNFT.sol";

contract NFTTest is Test {
    NebuloidsNFT nft;
    string hiddenUri =
        "ipfs://bafkreihxcamsslcsfjp2hvn42x6xh4i2jogrxjmvkx725y3nzwsfzeajfe/";

    function setUp() public {
        nft = new NebuloidsNFT(hiddenUri);
        vm.deal(address(1), 100 ether);
    }

    function test_CantMintRound0() public {
        vm.expectRevert(Nebuloids__MaxRoundMintExceeded.selector);
        nft.mint(5);
    }

    function test_CantMintAt0Amount() public {
        vm.startPrank(address(1));
        vm.expectRevert(Nebuloids__MaxMintExceeded.selector);
        nft.mint(0);
        vm.stopPrank();
    }

    function test_ownership() public {
        assertEq(nft.owner(), address(this));
    }

    function test_StartRound1() public {
        nft.startRound(85, 0.1 ether, "");
        (
            string memory uri,
            uint start,
            uint total,
            uint minted,
            uint256 price
        ) = nft.rounds(1);
        assertEq(nft.currentRound(), 1);
        assertEq(total, 85);
        assertEq(price, 0.1 ether);
        assertEq(minted, 0);
        assertEq(start, 1);
        assertEq(uri, "");
    }

    function test_mintOnly5() public {
        nft.startRound(85, 0.1 ether, "");
        vm.startPrank(address(1));
        nft.mint{value: 0.5 ether}(5);
        assertEq(nft.balanceOf(address(1)), 5);
        vm.expectRevert(Nebuloids__MaxMintExceeded.selector);
        nft.mint{value: 0.1 ether}(1);
        vm.stopPrank();
    }

    function test_mintOnlyWithFunds() public {
        nft.startRound(85, 0.1 ether, "");
        vm.startPrank(address(1));
        vm.expectRevert(Nebuloids__InsufficientFunds.selector);
        nft.mint{value: 0.05 ether}(1);
        vm.stopPrank();
    }

    function test_OwnerCanMintWithoutFee() public {
        nft.startRound(85, 0.1 ether, "");
        nft.transferOwnership(address(1));
        vm.startPrank(address(1));
        nft.mint(5);
        assertEq(nft.balanceOf(address(1)), 5);
        vm.stopPrank();
    }

    function test_OwnerCanMintAnyAmountBelowMax() public {
        nft.startRound(85, 0.1 ether, "");
        nft.transferOwnership(address(1));
        vm.startPrank(address(1));
        nft.mint(85);
        assertEq(nft.balanceOf(address(1)), 85);
        vm.expectRevert(Nebuloids__MaxRoundMintExceeded.selector);
        nft.mint(2);
        vm.stopPrank();

        (, , uint total, uint minted, ) = nft.rounds(1);
        assertEq(minted, 85);
        assertEq(total, 85);
    }

    function test_appropriateUriIsShown() public {
        nft.startRound(85, 0.1 ether, "");
        vm.startPrank(address(1));
        nft.mint{value: 0.5 ether}(5);
        assertEq(nft.balanceOf(address(1)), 5);
        vm.stopPrank();
        assertEq(nft.tokenURI(1), hiddenUri);

        nft.setUri(1, "stuffWhoo/");
        assertEq(nft.tokenURI(1), "stuffWhoo/1");
    }

    function test_nextRoundIsOK() public {
        nft.startRound(5, 0.1 ether, "");

        nft.transferOwnership(address(1));
        vm.startPrank(address(1));
        nft.mint(5);
        assertEq(nft.balanceOf(address(1)), 5);

        nft.startRound(10, 0.1 ether, "");

        (, uint start, uint total, uint minted, ) = nft.rounds(2);
        assertEq(start, 6);
        assertEq(total, 10);
        assertEq(minted, 0);

        nft.mint(4);
        assertEq(nft.balanceOf(address(1)), 9);
        vm.stopPrank();

        (, , , minted, ) = nft.rounds(2);

        assertEq(minted, 4);
        assertEq(nft.totalSupply(), 9);

        assertEq(nft.roundIdOf(6), 2);
        assertEq(nft.roundIdOf(9), 2);
    }
}
