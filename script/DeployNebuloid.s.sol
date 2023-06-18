// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {NebuloidsNFT} from "../src/NebuloidsNFT.sol";

contract CounterScript is Script {
    function run() public {
        vm.startBroadcast();
        new NebuloidsNFT(
            "ipfs://bafkreihxcamsslcsfjp2hvn42x6xh4i2jogrxjmvkx725y3nzwsfzeajfe/"
        );
        vm.stopBroadcast();
    }
}
