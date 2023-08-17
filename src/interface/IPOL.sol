//SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

interface IToken {
    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    function balanceOf(address _user) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function burn(uint256 amount) external;

    function burnFrom(address owner, uint256 amount) external;

    function mint(address to, uint256 amount) external;
}

interface IPOL is IToken {
    function addLiquidity(
        uint256 min_liquidity,
        uint256 max_tokens,
        uint256 base_amount
    ) external returns (uint256);

    function removeLiquidity(
        uint256 amount,
        uint256 min_base,
        uint256 min_tokens
    ) external returns (uint256, uint256);

    function swap(
        uint256 base_input,
        uint256 token_input,
        uint256 base_output,
        uint256 token_output,
        uint256 min_intout,
        address _to
    ) external returns (uint256 _output);

    function getBaseToLiquidityInputPrice(
        uint256 base_amount
    )
        external
        view
        returns (uint256 liquidity_minted, uint256 token_amount_needed);

    function outputTokens(
        uint256 _amount,
        bool isDesired
    ) external view returns (uint256);

    function outputBase(
        uint256 _amount,
        bool isDesired
    ) external view returns (uint256);

    function addLiquidityFromBase(
        uint256 _base_amount
    ) external returns (uint256);

    function removeLiquidityToBase(
        uint256 _liquidity,
        uint256 _tax
    ) external returns (uint256 _base);
}
