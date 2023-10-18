// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.19;

import "../amm/interfaces/IAmmRouter02.sol";
import "openzeppelin/token/ERC20/IERC20.sol";

interface IPOLv2Router is IAmmRouter02 {
    function getSells(
        IERC20 token,
        address trader
    ) external view returns (uint256 amountSold, uint256 lastSell);

    function getFees(
        IERC20 token
    )
        external
        view
        returns (uint16 buyFee, uint16 sellFee, uint256 maxDailySell);
}
