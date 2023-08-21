//SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "openzeppelin/token/ERC20/IERC20.sol";

interface IERC20Mintable is IERC20 {
    function mint(address to, uint256 amount) external;
}

interface IPOL is IERC20Mintable {
    function addLiquidity(
        uint256 _minLiquidity,
        uint256 _maxTokens,
        uint256 _baseAmount
    ) external returns (uint256);

    function removeLiquidity(
        uint256 _amount,
        uint256 _minBase,
        uint256 _minTokens
    ) external returns (uint256, uint256);

    function swap(
        uint256 _baseInput,
        uint256 _tokenInput,
        uint256 _baseOutput,
        uint256 _tokenOutput,
        uint256 _minIntout,
        address _to
    ) external returns (uint256 _output);

    function getBaseToLiquidityInputPrice(
        uint256 _baseAmount
    )
        external
        view
        returns (uint256 liquidityMinted_, uint256 tokenAmountNeeded_);

    function outputTokens(
        uint256 _amount,
        bool _isDesired
    ) external view returns (uint256);

    function outputBase(
        uint256 _amount,
        bool _isDesired
    ) external view returns (uint256);

    function addLiquidityFromBase(
        uint256 _baseAmount
    ) external returns (uint256);

    function removeLiquidityToBase(
        uint256 _liquidity,
        uint256 _tax
    ) external returns (uint256 base_);
}
