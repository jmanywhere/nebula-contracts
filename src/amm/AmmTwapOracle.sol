// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.19;

import "./Whitelist.sol";
import "./interfaces/IAmmPair.sol";
import "./interfaces/IAmmTwapOracle.sol";
import "./lib/FixedPoint.sol";
import "./lib/AmmLibrary.sol";
import "./lib/AmmOracleLibrary.sol";

// fixed window oracle that recomputes the average price for the entire period once every period
// note that the price average is only guaranteed to be over at least 1 period, but may be over a longer period
// note this is a singleton oracle and only needs to be deployed once per desired parameter
// the goal of this oracle is to be always available under all possible update conditions
// oracle will always use data published outside of the current block
contract AmmTwapOracle is Whitelist, IAmmTwapOracle {
    using FixedPoint for *;

    struct Observation {
        uint32 timestamp;
        uint commit_block;
        uint price0Cumulative;
        uint price1Cumulative;
        FixedPoint.uq112x112 price0Average;
        FixedPoint.uq112x112 price1Average;
        FixedPoint.uq112x112 prev_price0Average;
        FixedPoint.uq112x112 prev_price1Average;
    }

    address public immutable factory;

    //this is the size of the fixed period
    uint32 public periodSize;
    uint public constant MIN_BLOCKS = 3;

    // mapping from pair address to a list of price observations of that pair
    mapping(address => Observation) public pairObservation;
    address[] registry;

    event UpdatePeriodSize(uint32 old_period_size, uint32 period_size);

    constructor(address factory_, uint32 periodSize_) Whitelist(msg.sender) {
        require(
            periodSize_ > 1 minutes,
            "periodSize must be greater than 60 seconds"
        );
        factory = factory_;

        emit UpdatePeriodSize(periodSize, periodSize_);

        periodSize = periodSize_;
    }

    //Update minimum period before update of a pair
    function updatePeriodSize(
        uint32 periodSize_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            periodSize_ > 1 minutes,
            "periodSize must be greater than 60 seconds"
        );

        emit UpdatePeriodSize(periodSize, periodSize_);

        periodSize = periodSize_;
    }

    // performs chained update calculations on any number of pairs
    //whitelisted to avoid DDOS attacks since new pairs will be registered
    function updatePath(address[] memory path) public onlyWhitelisted {
        require(path.length >= 2, "AmmLibrary: INVALID_PATH");
        for (uint i; i < path.length - 1; i++) {
            update(path[i], path[i + 1]);
        }
    }

    //updates all pairs registered
    //returns the amount of pairs updated
    function updateAll() public returns (uint updatedPairs) {
        IAmmPair pair;
        bool success;
        for (uint i; i < registry.length; i++) {
            pair = IAmmPair(registry[i]);
            (success, , ) = update(pair.token0(), pair.token1());
            if (success) {
                updatedPairs++;
            }
        }
    }

    // performs chained getAmountOut calculations on any number of pairs
    function consultAmountsOut(
        uint amountIn,
        address[] memory path
    ) public view returns (uint[] memory amounts) {
        require(path.length >= 2, "AmmLibrary: INVALID_PATH");
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        for (uint i; i < path.length - 1; i++) {
            amounts[i + 1] = consult(path[i], amounts[i], path[i + 1]);
        }
    }

    // returns the amount out corresponding to the amount in for a given token using the moving average over the time
    // Uses the last precomputed price average
    function consult(
        address tokenIn,
        uint amountIn,
        address tokenOut
    ) public view returns (uint amountOut) {
        address pair = AmmLibrary.pairFor(factory, tokenIn, tokenOut);
        Observation storage observation = pairObservation[pair];

        require(
            observation.timestamp > 0,
            "PcsPeriodicOracle: PAIR_UNINITIALIZED"
        );

        (address token0, ) = AmmLibrary.sortTokens(tokenIn, tokenOut);

        uint lapsedBlocks = block.number - observation.commit_block;

        //Used the latest price if we are outside the window of a flashloan
        if (lapsedBlocks >= MIN_BLOCKS) {
            if (token0 == tokenIn) {
                return observation.price0Average.mul(amountIn).decode144();
            } else {
                return observation.price1Average.mul(amountIn).decode144();
            }

            //Use the last price during the reveal window
        } else {
            if (token0 == tokenIn) {
                return observation.prev_price0Average.mul(amountIn).decode144();
            } else {
                return observation.prev_price1Average.mul(amountIn).decode144();
            }
        }
    }

    // update the cumulative price for the observation at the current timestamp. each observation is updated at most
    // once per epoch period.
    function update(
        address tokenA,
        address tokenB
    ) private returns (bool success, address pair, uint32 timestamp) {
        pair = AmmLibrary.pairFor(factory, tokenA, tokenB);

        Observation storage observation = pairObservation[pair];

        //add to registry if new
        if (observation.timestamp == 0) {
            registry.push(pair);

            //get latest historical
            (, , observation.timestamp) = IAmmPair(pair).getReserves();
            observation.price0Cumulative = IAmmPair(pair)
                .price0CumulativeLast();
            observation.price1Cumulative = IAmmPair(pair)
                .price1CumulativeLast();
        }

        (
            uint price0Cumulative,
            uint price1Cumulative,
            uint32 blockTimestamp
        ) = AmmOracleLibrary.currentCumulativePrices(pair);

        // we only want to commit updates once per period (i.e. windowSize / granularity)
        uint32 timeElapsed = blockTimestamp - observation.timestamp;
        if (timeElapsed > periodSize || observation.commit_block == 0) {
            //save old average
            observation.prev_price0Average = observation.price0Average;
            observation.prev_price1Average = observation.price1Average;

            //update average
            observation.price0Average = FixedPoint.uq112x112(
                uint224(
                    (price0Cumulative - observation.price0Cumulative) /
                        timeElapsed
                )
            );
            observation.price1Average = FixedPoint.uq112x112(
                uint224(
                    (price1Cumulative - observation.price1Cumulative) /
                        timeElapsed
                )
            );

            //if the block is not initialized we to set the previous price
            if (observation.commit_block == 0) {
                observation.prev_price0Average = observation.price0Average;
                observation.prev_price1Average = observation.price1Average;
            }

            observation.commit_block = block.number;
            observation.timestamp = blockTimestamp;
            observation.price0Cumulative = price0Cumulative;
            observation.price1Cumulative = price1Cumulative;

            success = true;
        }

        timestamp = observation.timestamp;
    }
}
