// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.19;

import "../amm/interfaces/IAmmFactory.sol";

interface IPOLv2Factory is IAmmFactory {
    function router() external view returns (address);
}
