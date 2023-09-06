//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "openzeppelin/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import "../src/POL.sol";

contract TestPOLv2 is Test {
    POLv2 public pol;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event OnAddLiquidity(
        address indexed provider,
        uint256 liquidityAmount,
        uint256 _tokenBAmount,
        uint256 tokenAAmount
    );
    event OnRemoveLiquidity(
        address indexed provider,
        uint256 liquidityAmount,
        uint256 _tokenBAmount,
        uint256 tokenAAmount
    );
    event Swap(
        address indexed _user,
        uint256 _tokenBInput,
        uint256 _tokenAInput,
        uint256 _tokenBOutput,
        uint256 _tokenAOutput
    );
    event Fee(address indexed _user, uint256 _tokenAFee, uint256 _tokenBFee);

    ERC20PresetFixedSupply public tokenA;
    ERC20PresetFixedSupply public tokenB;

    address[] public users;

    function setUp() public {
        tokenA = new ERC20PresetFixedSupply(
            "tokenA",
            "tka",
            1_000_000 ether,
            address(this)
        );
        tokenB = new ERC20PresetFixedSupply(
            "tokenB",
            "tkb",
            1_000_000 ether,
            address(this)
        );
        pol = new POLv2(tokenA, tokenB, "POL_LP_tokenA-tokenB", "LP_tka-tkb");
        pol.setTreasury(makeAddr("treasury"));

        users.push(makeAddr("user0"));
        users.push(makeAddr("user1"));
        users.push(makeAddr("user2"));
        users.push(makeAddr("user3"));

        tokenA.approve(address(pol), 1_000_000 ether);
        tokenB.approve(address(pol), 1_000_000 ether);

        tokenA.transfer(users[0], 1000 ether);
        tokenA.transfer(users[1], 1000 ether);
        tokenA.transfer(users[2], 1000 ether);
        tokenA.transfer(users[3], 1000 ether);
        tokenB.transfer(users[0], 1000 ether);
        tokenB.transfer(users[1], 1000 ether);
        tokenB.transfer(users[2], 1000 ether);
        tokenB.transfer(users[3], 1000 ether);
    }

    function test_constructorSetParams() public {
        assertEq(pol.name(), "POL_LP_tokenA-tokenB");
        assertEq(pol.symbol(), "LP_tka-tkb");
        assertTrue(pol.hasRole(pol.MANAGER_ROLE(), address(this)));
        assertEq(pol.getRoleAdmin(pol.WHITELIST_ROLE()), pol.MANAGER_ROLE());
        assertEq(pol.getRoleAdmin(pol.NOSELLLIMIT_ROLE()), pol.MANAGER_ROLE());
        assertEq(address(pol.tokenA()), address(tokenA));
        assertEq(address(pol.tokenB()), address(tokenB));
        assertTrue(1 < 10 ** tokenB.decimals());
    }

    function testFuzz_addLiquidityRevertIfInvalidMinLiquidity(
        uint256 _maxTokenA,
        uint256 _tokenBAmount
    ) public {
        vm.expectRevert(InvalidArguments.selector);
        pol.addLiquidity(0, _maxTokenA, _tokenBAmount);
    }

    function testFuzz_addLiquidityRevertIfInvalidMaxTokenA(
        uint256 _minLiquidity,
        uint256 _tokenBAmount
    ) public {
        vm.expectRevert(InvalidArguments.selector);
        pol.addLiquidity(_minLiquidity, 0, _tokenBAmount);
    }

    function testFuzz_addLiquidityRevertIfInvalidTokenBAmount(
        uint256 _minLiquidity,
        uint256 _maxTokenA
    ) public {
        vm.expectRevert(InvalidArguments.selector);
        pol.addLiquidity(_minLiquidity, _maxTokenA, 0);
    }

    function testFuzz_removeLiquidityRevertIfInvalidAmount(
        uint256 _tokenA,
        uint256 _tokenB
    ) public {
        vm.expectRevert(InvalidArguments.selector);
        pol.removeLiquidity(0, _tokenB, _tokenA);
    }

    function testFuzz_removeLiquidityRevertIfInvalidTokenA(
        uint256 _amount,
        uint256 _tokenA
    ) public {
        vm.expectRevert(InvalidArguments.selector);
        pol.removeLiquidity(_amount, 0, _tokenA);
    }

    function testFuzz_removeLiquidityRevertIfInvalidTokenB(
        uint256 _amount,
        uint256 _tokenB
    ) public {
        vm.expectRevert(InvalidArguments.selector);
        pol.removeLiquidity(_amount, _tokenB, 0);
    }

    function testFuzz_addLiquidityRevertIfInvalidInitialLiquidityTokenA(
        uint256 _minLiquidity,
        uint256 _maxTokenA,
        uint256 _tokenBAmount
    ) public {
        vm.assume(_minLiquidity > 0);
        vm.assume(_maxTokenA > 0);
        vm.assume(_tokenBAmount > 0);
        uint256 revertCap = (10 ** (tokenA.decimals() / 4)) - 1;
        vm.expectRevert(InvalidInitialLiquidity.selector);
        pol.addLiquidity(_minLiquidity, _maxTokenA % revertCap, _tokenBAmount);
    }

    function testFuzz_addLiquidityRevertIfInvalidInitialLiquidityTokenB(
        uint256 _minLiquidity,
        uint256 _maxTokenA,
        uint256 _tokenBAmount
    ) public {
        vm.assume(_minLiquidity > 0);
        vm.assume(_maxTokenA > 0);
        vm.assume(_tokenBAmount > 0);
        uint256 revertCap = (10 ** (tokenB.decimals() / 4)) - 1;
        vm.expectRevert(InvalidInitialLiquidity.selector);
        pol.addLiquidity(_minLiquidity, _maxTokenA, _tokenBAmount % revertCap);
    }

    function testFuzz_addLiquidityRevertIfInvalidInitialLiquidityRatio(
        uint64 _tokenBAmount
    ) public {
        vm.assume(_tokenBAmount > 0);
        uint256 tokenBAmount = uint256(_tokenBAmount); //So that ratio will always be greater than 2*64
        vm.expectRevert(InvalidInitialLiquidity.selector);
        pol.addLiquidity(1, UINT256_MAX, tokenBAmount);
    }

    function testFuzz_addLiquidityMintLiquidityToSenderInitial(
        uint256 _maxTokenA,
        uint256 _tokenBAmount
    ) public {
        uint256 minWad = 1 ether;
        uint256 maxTokenA = (_maxTokenA %
            (tokenA.balanceOf(address(this)) - minWad)) + minWad;
        uint256 tokenBAmount = (_tokenBAmount %
            (tokenB.balanceOf(address(this)) - minWad)) + minWad;
        tokenA.approve(address(pol), maxTokenA);
        tokenB.approve(address(pol), tokenBAmount);
        uint256 minLiquidity = tokenBAmount;

        //tokenA transfer event
        vm.expectEmit(address(tokenA));
        emit Transfer(address(this), address(pol), maxTokenA);
        //tokenB transfer event
        vm.expectEmit(address(tokenB));
        emit Transfer(address(this), address(pol), tokenBAmount);
        //pol mint transfer event
        vm.expectEmit(address(pol));
        emit Transfer(address(0), address(this), tokenBAmount);
        //liquidity add event
        vm.expectEmit(address(pol));
        emit OnAddLiquidity(
            address(this),
            minLiquidity,
            tokenBAmount,
            maxTokenA
        );

        uint256 liqMinted = pol.addLiquidity(
            minLiquidity,
            maxTokenA,
            tokenBAmount
        );

        uint256 liqBalance = pol.balanceOf(address(this));

        assertEq(liqBalance, liqMinted);
        assertEq(tokenBAmount, liqMinted);
    }

    function testFuzz_addLiquidityMintLiquidityToSenderPostInitial(
        uint256 _maxTokenAFirst,
        uint256 _tokenBAmountFirst,
        uint256 _tokenBAmount,
        uint256 _userIndex
    ) public {
        testFuzz_addLiquidityMintLiquidityToSenderInitial(
            _maxTokenAFirst,
            _tokenBAmountFirst
        );

        address user = users[_userIndex % 4];

        uint256 minWad = 1 ether; //18 decimals / 4
        uint256 tokenBAmount = (_tokenBAmount %
            (tokenB.balanceOf(user) - minWad)) + minWad;

        (uint256 liquidityGen, uint256 tokenAAmount) = pol
            .getTokenBToLiquidityInputPrice(tokenBAmount);

        vm.assume(tokenA.balanceOf(user) >= tokenAAmount);

        vm.prank(user);
        tokenA.approve(address(pol), tokenAAmount);
        vm.prank(user);
        tokenB.approve(address(pol), tokenBAmount);

        //tokenA transfer event
        vm.expectEmit(address(tokenA));
        emit Transfer(user, address(pol), tokenAAmount);
        //tokenB transfer event
        vm.expectEmit(address(tokenB));
        emit Transfer(user, address(pol), tokenBAmount);
        //pol mint transfer event
        vm.expectEmit(address(pol));
        emit Transfer(address(0), user, tokenBAmount);
        //liquidity add event
        vm.expectEmit(address(pol));
        emit OnAddLiquidity(user, tokenBAmount, tokenBAmount, tokenAAmount);

        vm.prank(user);
        uint256 liqMinted = pol.addLiquidity(
            liquidityGen,
            tokenAAmount,
            tokenBAmount
        );

        uint256 liqBalance = pol.balanceOf(user);
        assertEq(liqBalance, liqMinted);

        assertEq(tokenBAmount, liquidityGen);
    }

    function testFuzz_removeLiquidity(
        uint256 _maxTokenAFirst,
        uint256 _tokenBAmountFirst,
        uint256 _tokenBAmount,
        uint256 _userIndex,
        uint256 _liqToRemove
    ) public {
        address user = users[_userIndex % 4];
        uint256 userTokenAInitial = tokenA.balanceOf(user);
        uint256 userTokenBInitial = tokenA.balanceOf(user);

        uint256 minWad = 1 ether;
        uint256 tokenBAdd = (_tokenBAmount %
            (tokenB.balanceOf(user) - minWad)) + minWad;

        testFuzz_addLiquidityMintLiquidityToSenderPostInitial(
            _maxTokenAFirst,
            _tokenBAmountFirst,
            tokenBAdd,
            _userIndex
        );

        uint256 liquidityGen = pol.balanceOf(user);
        uint256 tokenAAmount = userTokenAInitial - tokenA.balanceOf(user);
        uint256 tokenBAmount = userTokenBInitial - tokenB.balanceOf(user);

        emit log_uint(liquidityGen);

        uint256 removedLiq = (_liqToRemove % ((liquidityGen * 3) / 4)) +
            (liquidityGen / 4);
        uint256 expectedTokenA = (tokenAAmount * removedLiq) / liquidityGen;
        uint256 expectedTokenB = (tokenBAmount * removedLiq) / liquidityGen;
        if (expectedTokenA == 0) {
            removedLiq = liquidityGen;
            expectedTokenA = tokenAAmount;
            expectedTokenB = tokenBAmount;
        }

        vm.prank(user);
        (uint256 receivedTokenB, uint256 receivedTokenA) = pol.removeLiquidity(
            removedLiq,
            expectedTokenB,
            expectedTokenA - 1
        );

        uint256 liqBalance = pol.balanceOf(user);

        assertEq(liqBalance, liquidityGen - removedLiq);
        assertGe(receivedTokenA, expectedTokenA - 1);
        assertLe(receivedTokenA, expectedTokenA);
        assertGe(receivedTokenB, expectedTokenB - 1);
        assertLe(receivedTokenB, expectedTokenB);
    }

    function testFuzz_swapInputTokenB(
        uint256 _maxTokenAFirst,
        uint256 _tokenBAmountFirst,
        uint256 _tokenBAmount,
        uint256 _userIndex,
        uint256 _liqToRemove,
        uint256 _swapWad,
        uint256 _userSwapperIndex
    ) public {
        testFuzz_removeLiquidity(
            _maxTokenAFirst,
            _tokenBAmountFirst,
            _tokenBAmount,
            _userIndex,
            _liqToRemove
        );
        uint256 invariant0 = ((tokenA.balanceOf(address(pol)) / 10 ** 9) *
            (tokenB.balanceOf(address(pol)) / 10 ** 9)) / 10 ** 9;

        uint256 minWad = 1 ether;
        address user = users[_userSwapperIndex % 4];

        //input token B
        uint256 tokenABal0 = tokenA.balanceOf(user);
        uint256 tokenBBal0 = tokenB.balanceOf(user);
        uint256 swapWadTokenBInput = (_swapWad %
            (tokenB.balanceOf(user) - minWad)) + minWad;
        (uint256 expectedOutputTokenA, , ) = pol.outputTokenA(
            swapWadTokenBInput,
            false,
            false
        );
        vm.prank(user);
        tokenB.approve(address(pol), swapWadTokenBInput);
        vm.prank(user);
        pol.swap(swapWadTokenBInput, 0, 0, 0, expectedOutputTokenA - 1, user);
        uint256 tokenABal1 = tokenA.balanceOf(user);
        uint256 tokenBBal1 = tokenB.balanceOf(user);
        uint256 invariant = ((tokenA.balanceOf(address(pol)) / 10 ** 9) *
            (tokenB.balanceOf(address(pol)) / 10 ** 9)) / 10 ** 9;
        assertApproxEqAbs(tokenABal1 - tokenABal0, expectedOutputTokenA, 10);
        assertApproxEqAbs(tokenBBal0 - tokenBBal1, swapWadTokenBInput, 10);
        assertApproxEqAbs(invariant0, invariant, 10 ** 9);
    }

    function testFuzz_swapInputTokenA(
        uint256 _maxTokenAFirst,
        uint256 _tokenBAmountFirst,
        uint256 _tokenBAmount,
        uint256 _userIndex,
        uint256 _liqToRemove,
        uint256 _swapWad,
        uint256 _userSwapperIndex
    ) public {
        testFuzz_removeLiquidity(
            _maxTokenAFirst,
            _tokenBAmountFirst,
            _tokenBAmount,
            _userIndex,
            _liqToRemove
        );
        uint256 invariant0 = ((tokenA.balanceOf(address(pol)) / 10 ** 9) *
            (tokenB.balanceOf(address(pol)) / 10 ** 9)) / 10 ** 9;
        uint256 minWad = 1 ether;
        uint256 maxDailySell = pol.maxDailySell();
        address user = users[_userSwapperIndex % 4];

        //input token A
        uint256 tokenABal0 = tokenA.balanceOf(user);
        uint256 tokenBBal0 = tokenB.balanceOf(user);
        uint256 swapWadTokenAInput = (_swapWad %
            (tokenA.balanceOf(user) - minWad)) + minWad;
        if (swapWadTokenAInput > maxDailySell)
            swapWadTokenAInput = maxDailySell;
        (uint256 expectedOutputTokenB, , ) = pol.outputTokenB(
            swapWadTokenAInput,
            false,
            false
        );
        vm.prank(user);
        tokenA.approve(address(pol), swapWadTokenAInput);
        vm.prank(user);
        pol.swap(0, swapWadTokenAInput, 0, 0, expectedOutputTokenB - 1, user);
        uint256 tokenABal1 = tokenA.balanceOf(user);
        uint256 tokenBBal1 = tokenB.balanceOf(user);
        uint256 invariant = ((tokenA.balanceOf(address(pol)) / 10 ** 9) *
            (tokenB.balanceOf(address(pol)) / 10 ** 9)) / 10 ** 9;
        assertApproxEqAbs(tokenBBal1 - tokenBBal0, expectedOutputTokenB, 10);
        assertApproxEqAbs(tokenABal0 - tokenABal1, swapWadTokenAInput, 10);
        assertApproxEqAbs(invariant0, invariant, 10 ** 9);
    }

    function testFuzz_swapInputTokenBWithFee(
        uint256 _maxTokenAFirst,
        uint256 _tokenBAmountFirst,
        uint256 _tokenBAmount,
        uint256 _userIndex,
        uint256 _liqToRemove,
        uint256 _swapWad,
        uint256 _userSwapperIndex
    ) public {
        testFuzz_removeLiquidity(
            _maxTokenAFirst,
            _tokenBAmountFirst,
            _tokenBAmount,
            _userIndex,
            _liqToRemove
        );

        pol.setTaxes(200, 150, 75, 800);

        uint256 invariant0 = ((tokenA.balanceOf(address(pol)) / 10 ** 9) *
            (tokenB.balanceOf(address(pol)) / 10 ** 9)) / 10 ** 9;

        uint256 minWad = 1 ether;
        address user = users[_userSwapperIndex % 4];

        //input token B
        uint256 tokenABal0 = tokenA.balanceOf(user);
        uint256 tokenBBal0 = tokenB.balanceOf(user);
        uint256 swapWadTokenBInput = (_swapWad %
            (tokenB.balanceOf(user) - minWad)) + minWad;
        (uint256 expectedOutputTokenA, , ) = pol.outputTokenA(
            swapWadTokenBInput,
            false,
            true
        );
        vm.prank(user);
        tokenB.approve(address(pol), swapWadTokenBInput);
        vm.prank(user);
        pol.swap(swapWadTokenBInput, 0, 0, 0, expectedOutputTokenA - 1, user);
        uint256 tokenABal1 = tokenA.balanceOf(user);
        uint256 tokenBBal1 = tokenB.balanceOf(user);
        uint256 invariant = ((tokenA.balanceOf(address(pol)) / 10 ** 9) *
            (tokenB.balanceOf(address(pol)) / 10 ** 9)) / 10 ** 9;
        assertApproxEqAbs(tokenABal1 - tokenABal0, expectedOutputTokenA, 10);
        assertApproxEqAbs(tokenBBal0 - tokenBBal1, swapWadTokenBInput, 10);
        assertApproxEqAbs(invariant0, invariant, 10 ** 9);
    }

    function testFuzz_swapInputTokenAWithFee(
        uint256 _maxTokenAFirst,
        uint256 _tokenBAmountFirst,
        uint256 _tokenBAmount,
        uint256 _userIndex,
        uint256 _liqToRemove,
        uint256 _swapWad,
        uint256 _userSwapperIndex
    ) public {
        testFuzz_removeLiquidity(
            _maxTokenAFirst,
            _tokenBAmountFirst,
            _tokenBAmount,
            _userIndex,
            _liqToRemove
        );

        pol.setTaxes(200, 150, 75, 800);

        uint256 invariant0 = ((tokenA.balanceOf(address(pol)) / 10 ** 9) *
            (tokenB.balanceOf(address(pol)) / 10 ** 9)) / 10 ** 9;

        uint256 minWad = 1 ether;
        address user = users[_userSwapperIndex % 4];

        //input token B
        uint256 tokenABal0 = tokenA.balanceOf(user);
        uint256 tokenBBal0 = tokenB.balanceOf(user);
        uint256 swapWadTokenAInput = (_swapWad %
            (tokenA.balanceOf(user) - minWad)) + minWad;
        (uint256 expectedOutputTokenB, , ) = pol.outputTokenB(
            swapWadTokenAInput,
            false,
            true
        );
        vm.prank(user);
        tokenA.approve(address(pol), swapWadTokenAInput);
        vm.prank(user);
        pol.swap(0, swapWadTokenAInput, 0, 0, expectedOutputTokenB - 1, user);
        uint256 tokenABal1 = tokenA.balanceOf(user);
        uint256 tokenBBal1 = tokenB.balanceOf(user);
        uint256 invariant = ((tokenA.balanceOf(address(pol)) / 10 ** 9) *
            (tokenB.balanceOf(address(pol)) / 10 ** 9)) / 10 ** 9;
        assertApproxEqAbs(tokenBBal1 - tokenBBal0, expectedOutputTokenB, 10);
        assertApproxEqAbs(tokenABal0 - tokenABal1, swapWadTokenAInput, 10);
        assertApproxEqAbs(invariant0, invariant, 10 ** 9);
    }

    function test_addLiquidityAboveMaximumTokenA() public {
        pol.addLiquidity(1 ether, 2 ether, 1 ether);
        address user = users[0];
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                AboveMaximum.selector,
                0.5 ether,
                2 ether + 1
            )
        );
        pol.addLiquidity(1, 0.5 ether, 1 ether);
    }

    function test_addLiquidityBelowMinLiquidity() public {
        pol.addLiquidity(1 ether, 2 ether, 1 ether);
        address user = users[0];
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(BelowMinimum.selector, 2.1 ether, 2 ether)
        );
        pol.addLiquidity(2.1 ether, 4 ether + 1, 2 ether);
    }

    function test_removeLiquidityBelowMinimumTokenB() public {
        pol.addLiquidity(1 ether, 2 ether, 1 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                BelowMinimum.selector,
                0.5 ether,
                0.5 ether + 1
            )
        );
        pol.removeLiquidity(0.5 ether, 0.5 ether + 1, 1 ether);
    }

    function test_removeLiquidityBelowMinimumTokenA() public {
        pol.addLiquidity(1 ether, 2 ether, 1 ether);
        vm.expectRevert(
            abi.encodeWithSelector(BelowMinimum.selector, 1 ether, 1 ether + 1)
        );
        pol.removeLiquidity(0.5 ether, 0.5 ether, 1 ether + 1);
    }
}
