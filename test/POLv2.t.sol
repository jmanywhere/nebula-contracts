//SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import "openzeppelin/token/ERC20/presets/ERC20PresetFixedSupply.sol";

import "../src/amm/lib/WETH.sol";
import "../src/POLv2Factory.sol";
import "../src/POLv2Router.sol";
import "../src/POLv2Library.sol";
import "../src/POLv2Pair.sol";

contract POLv2Test is Test {
    ERC20PresetFixedSupply public tokenA;
    ERC20PresetFixedSupply public tokenB;

    WETH public weth;
    POLv2Router public router;

    address[] public users;

    function setUp() public {
        users.push(makeAddr("user0"));
        users.push(makeAddr("user1"));
        users.push(makeAddr("user2"));
        users.push(makeAddr("user3"));

        weth = new WETH();
        router = new POLv2Router(users[0], address(weth));

        vm.deal(users[0], 100 ether);

        tokenA = new ERC20PresetFixedSupply(
            "tokenA",
            "TA",
            1_000_000_000 ether,
            address(users[0])
        );
        tokenB = new ERC20PresetFixedSupply(
            "tokenB",
            "TB",
            1_000_000_000 ether,
            address(users[0])
        );
        vm.startPrank(users[0]);
        POLv2Factory(router.factory()).setFeeTo(users[0]);
        vm.stopPrank();
    }

    function test_addLiquidity() public {
        vm.startPrank(users[0]);
        tokenA.approve(address(router), 100 ether);
        tokenB.approve(address(router), 100 ether);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            100 ether,
            100 ether,
            0,
            0,
            users[0],
            block.timestamp
        );
        vm.stopPrank();
    }

    function test_swapExactTokensForTokens() public {
        vm.startPrank(users[0]);
        tokenA.approve(address(router), 100 ether);
        tokenB.approve(address(router), 100 ether);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            100 ether,
            100 ether,
            0,
            0,
            users[0],
            block.timestamp
        );
        router.setFees(tokenA, 100, 250, 550 ether);
        router.setFees(tokenB, 150, 175, 550 ether);
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        tokenA.approve(address(router), 1000 ether);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            400 ether,
            10 ether,
            path,
            users[0],
            block.timestamp
        );
        vm.expectRevert(bytes("POLv2: Exceed max daily sell"));
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            600 ether,
            0 ether,
            path,
            users[0],
            block.timestamp
        );
        vm.expectRevert(bytes("POLv2: Exceed max daily sell"));
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            200 ether,
            0 ether,
            path,
            users[0],
            block.timestamp
        );
        router.setIsExempt(users[0], true);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            200 ether,
            0 ether,
            path,
            users[0],
            block.timestamp
        );
        router.setIsExempt(users[0], false);
        vm.expectRevert(bytes("POLv2: Exceed max daily sell"));
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            200 ether,
            0 ether,
            path,
            users[0],
            block.timestamp
        );
        vm.stopPrank();
    }
}
