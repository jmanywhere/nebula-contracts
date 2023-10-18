// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.19;

import "./interface/IPOLv2Factory.sol";
import "./POLv2Pair.sol";

contract POLv2Factory is IPOLv2Factory {
    bytes32 public constant INIT_CODE_PAIR_HASH =
        keccak256(abi.encodePacked(type(POLv2Pair).creationCode));

    address public feeTo;
    address public feeToSetter;
    address public router;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    constructor(address _feeToSetter, address _router) {
        feeToSetter = _feeToSetter;
        router = _router;
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair) {
        require(msg.sender == router, "POLv2: Not router");
        require(tokenA != tokenB, "Amm: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(token0 != address(0), "Amm: ZERO_ADDRESS");
        require(getPair[token0][token1] == address(0), "Amm: PAIR_EXISTS"); // single check is sufficient
        bytes memory bytecode = type(POLv2Pair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IAmmPair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, "Amm: FORBIDDEN");
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, "Amm: FORBIDDEN");
        feeToSetter = _feeToSetter;
    }

    function setRouter(address _router) external {
        require(msg.sender == feeToSetter, "Amm: FORBIDDEN");
        router = _router;
    }
}
