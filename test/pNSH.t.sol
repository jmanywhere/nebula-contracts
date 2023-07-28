// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
//  Contracts
import "../src/preLaunch/PreNSH.sol";
import "../src/preLaunch/WadingPool.sol";
import "openzeppelin/token/ERC20/IERC20.sol";

contract pNSH_Test is Test {
    WadingPool wadingPool;
    pNSH pnsh;
    IERC20 WETH;
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address stability = makeAddr("stability");
    IUniswapV2Router02 router;
    IUniswapV2Pair pair;

    function setUp() public {
        pnsh = new pNSH(stability);
        router = pnsh.uniswapV2Router();
        pair = IUniswapV2Pair(pnsh.mainPair());
        WETH = IERC20(router.WETH());
        wadingPool = new WadingPool(address(pnsh));

        pnsh.setWadingPool(address(wadingPool));

        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
    }

    function test_transfer() public {
        assertEq(pnsh.balanceOf(user1), 0);
        assertEq(pnsh.balanceOf(user2), 0);

        pnsh.transfer(user1, 100 ether);

        assertEq(pnsh.balanceOf(user1), 100 ether);
        assertEq(pnsh.balanceOf(user2), 0);
    }

    function test_addLiquidity() public {
        pnsh.approve(address(pnsh.uniswapV2Router()), 5_000_000_000 ether);

        router.addLiquidityETH{value: 50 ether}(
            address(pnsh),
            500_000_000 ether,
            500_000_000 ether,
            50 ether,
            address(this),
            block.timestamp
        );

        assertGt(pair.balanceOf(address(this)), 0);
        assertEq(pnsh.balanceOf(address(pair)), 500_000_000 ether);
        assertEq(WETH.balanceOf(address(pair)), 50 ether);
    }

    modifier addsLiquidity() {
        pnsh.approve(address(pnsh.uniswapV2Router()), 5_000_000_000 ether);

        router.addLiquidityETH{value: 50 ether}(
            address(pnsh),
            500_000_000 ether,
            500_000_000 ether,
            50 ether,
            address(this),
            block.timestamp
        );
        _;
    }

    function test_buy_fees() public addsLiquidity {
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(pnsh);

        vm.prank(user1);
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{
            value: 0.75 ether
        }(0, path, user1, block.timestamp);

        assertGt(pnsh.balanceOf(user1), 0);
        uint fee = pnsh.balanceOf(address(pnsh));
        assertEq(fee, pnsh.balanceOf(address(wadingPool)));
    }

    function test_sell_fees() public addsLiquidity {
        pnsh.transfer(user2, 5_000_000 ether);

        address[] memory path = new address[](2);
        path[0] = address(pnsh);
        path[1] = router.WETH();

        uint initBalance = user2.balance;

        vm.startPrank(user2);
        pnsh.approve(address(router), 5_000_000 ether);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            5_000_000 ether,
            0,
            path,
            user2,
            block.timestamp
        );

        assertEq(pnsh.balanceOf(user2), 0);
        assertGt(user2.balance, initBalance);
        uint fee = pnsh.balanceOf(address(pnsh));
        assertEq(fee, pnsh.balanceOf(address(wadingPool)));
    }

    function test_swap_fees_manual() public addsLiquidity {
        pnsh.transfer(user2, 5_000_000 ether);

        address[] memory path = new address[](2);
        path[0] = address(pnsh);
        path[1] = router.WETH();

        vm.startPrank(user2);
        pnsh.approve(address(router), 5_000_000 ether);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            5_000_000 ether,
            0,
            path,
            user2,
            block.timestamp
        );

        uint initBalace = stability.balance;

        pnsh.swapForStability();

        assertEq(pnsh.balanceOf(address(pnsh)), 0);
        assertGt(stability.balance, initBalace);
    }

    function test_swap_fees_auto() public addsLiquidity {
        pnsh.transfer(user2, 5_000_000 ether);
        pnsh.transfer(user1, 5_000_000 ether);

        address[] memory path = new address[](2);
        path[0] = address(pnsh);
        path[1] = router.WETH();

        vm.startPrank(user2);
        pnsh.approve(address(router), 5_000_000 ether);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            5_000_000 ether,
            0,
            path,
            user2,
            block.timestamp
        );

        uint initBalace = stability.balance;
        vm.startPrank(user1);
        pnsh.approve(address(router), 5_000_000 ether);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            1_000_000 ether,
            0,
            path,
            user2,
            block.timestamp
        );

        assertLt(pnsh.balanceOf(address(pnsh)), pnsh.threshold());
        assertGt(stability.balance, initBalace);
    }
}
