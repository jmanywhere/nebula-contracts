//SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "openzeppelin/token/ERC20/IERC20.sol";

interface IPOL {
    function addLiquidity(
        uint256 _minLiquidity,
        uint256 _maxTokens,
        uint256 _tokenBAmount
    ) external returns (uint256);

    function removeLiquidity(
        uint256 _amount,
        uint256 _minTokenB,
        uint256 _minTokenA
    ) external returns (uint256, uint256);

    function swap(
        uint256 _tokenBInput,
        uint256 _tokenAInput,
        uint256 _tokenBOutput,
        uint256 _tokenAOutput,
        uint256 _minIntout,
        address _to
    ) external returns (uint256 _output);

    function getTokenBToLiquidityInputPrice(
        uint256 _tokenBAmount
    ) external view returns (uint256 liquidityAmount_, uint256 tokenAAmount_);

    function outputTokenA(
        uint256 _amount,
        bool _isDesired,
        bool _withFee
    ) external view returns (uint256 other_, uint256 feeA_, uint256 feeB_);

    function outputTokenB(
        uint256 _amount,
        bool _isDesired,
        bool _withFee
    ) external view returns (uint256 other_, uint256 feeA_, uint256 feeB_);
}
