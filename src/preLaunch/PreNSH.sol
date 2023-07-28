// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

//---------------------------------------------------
// Imports
//---------------------------------------------------
import "openzeppelin/token/ERC20/ERC20.sol";
import "openzeppelin/access/Ownable.sol";
import "./IWadingPool.sol";
import "../interface/IUniswap.sol";
//---------------------------------------------------
// Errors
//---------------------------------------------------
error pNSH__Invalid_Fees();
error pNSH__Invalid_Address();
error pNSH__Invalid_Distribution();

contract pNSH is ERC20, Ownable {
    mapping(address user => bool status) public isExcludedFromFee;
    mapping(address user => bool status) public isLPAddress;
    IWadingPool public wadingPool;
    IUniswapV2Router02 public uniswapV2Router;
    address public mainPair;
    address public stability;
    address private WETH;
    uint public buyFee = 10;
    uint public sellFee = 10;
    uint public wadingDistribution = 5;
    uint public stabilityDistribution = 5;
    uint public threshold;
    bool private isSwapping;
    //---------------------------------------------------
    // Events
    //---------------------------------------------------
    event FeesUpdated(uint _buyFee, uint _sellFee);
    event DistributionUpdated(uint _dev, uint _wading);
    event LpAddressSet(address _lpAddress, bool _status);
    event UpdateExcludedAddress(address _toExclude, bool _newStatus);
    event BalanceTransferFailed(address _to, uint _amount);
    event SetWadingPool(address _wadingPool);
    event StabilityAddressChanged(address _newAddress);

    //---------------------------------------------------
    // Constructor
    //---------------------------------------------------
    constructor(address _stability) ERC20("preNSH", "pNSH") {
        if (_stability == address(0)) revert pNSH__Invalid_Address();
        stability = _stability;
        //------------------------
        // Setup router
        //------------------------
        uniswapV2Router = IUniswapV2Router02(
            //pancakeswap router
            0x10ED43C718714eb63d5aA57B78B54704E256024E
        );
        WETH = uniswapV2Router.WETH();
        mainPair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(
            address(this),
            WETH // BNB
        );
        isLPAddress[mainPair] = true;

        // We will BURN 32% of the total supply
        // 480 M tokens
        // Router needs to be approved to spend tokens
        _approve(address(this), address(uniswapV2Router), ~uint256(0));

        // exclude ourselves from fees
        isExcludedFromFee[address(this)] = true;
        isExcludedFromFee[owner()] = true;

        _mint(msg.sender, 1_500_000_000 ether);
        threshold = 250_000 ether;
    }

    receive() external payable {}

    //---------------------------------------------------
    // Public Functions
    //---------------------------------------------------
    function swapForStability() public {
        isSwapping = true;

        uint amount = balanceOf(address(this));
        address[] memory path = new address[](2);

        path[0] = address(this);
        path[1] = WETH;

        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount,
            0,
            path,
            address(this),
            block.timestamp
        );
        amount = address(this).balance;
        // In the case of an error, we will try again on the next transfer out. This is to avoid reverting the whole transaction
        (bool succ, ) = payable(stability).call{value: amount}("");
        if (!succ) emit BalanceTransferFailed(stability, amount);

        isSwapping = false;
    }

    //---------------------------------------------------
    // Owner Functions
    //---------------------------------------------------

    /**
     * Only owner can set up the fees
     * @param _buyFee New fee on Buy
     * @param _sellFee new Fee on Sell
     */
    function setFees(uint _buyFee, uint _sellFee) external onlyOwner {
        if (_buyFee > 10 || _sellFee > 10) {
            revert pNSH__Invalid_Fees();
        }
        buyFee = _buyFee;
        sellFee = _sellFee;
        emit FeesUpdated(_buyFee, _sellFee);
    }

    /**
     * Only owner can set up the LP address
     * @param _lpAddress Address to consider as LP token
     * @param _status Status of the LP address (true = LP, false = not LP)
     */
    function setLPAddress(address _lpAddress, bool _status) external onlyOwner {
        isLPAddress[_lpAddress] = _status;
        emit LpAddressSet(_lpAddress, _status);
    }

    /**
     * Only owner can set exclusions
     * @param _toExclude address to either exclude or include in fees
     * @param _newStatus status of the address (true = excluded, false = included)
     */
    function setExcludedAddress(
        address _toExclude,
        bool _newStatus
    ) external onlyOwner {
        isExcludedFromFee[_toExclude] = _newStatus;
        emit UpdateExcludedAddress(_toExclude, _newStatus);
    }

    /**
     * Sets the Wading pool which will spread rewards to all stakers in the Wading pool
     * @param _wadingPool Address of the wading pool
     */
    function setWadingPool(address _wadingPool) external onlyOwner {
        if (_wadingPool == address(0)) revert pNSH__Invalid_Address();
        isExcludedFromFee[_wadingPool] = false;
        wadingPool = IWadingPool(_wadingPool);
        _approve(address(this), _wadingPool, ~uint256(0));
        isExcludedFromFee[_wadingPool] = true;
        emit SetWadingPool(_wadingPool);
    }

    /**
     * Set the distribution of fees
     * @param _stability Proportion destined to the stabilty pool
     * @param _wading Proportion destined to the wading pool
     */
    function setDistribution(uint _stability, uint _wading) external onlyOwner {
        if (_stability + _wading != 10) revert pNSH__Invalid_Distribution();
        stabilityDistribution = _stability;
        wadingDistribution = _wading;
        emit DistributionUpdated(_stability, _wading);
    }

    function changeStability(address _newStability) external onlyOwner {
        if (_newStability == address(0)) revert pNSH__Invalid_Address();
        stability = _newStability;
        emit StabilityAddressChanged(_newStability);
    }

    //---------------------------------------------------
    // Internal Functions
    //---------------------------------------------------
    function _transfer(
        address from,
        address to,
        uint amount
    ) internal override {
        uint tax;
        bool[4] memory status = [
            isExcludedFromFee[from],
            isExcludedFromFee[to],
            isLPAddress[from],
            isLPAddress[to]
        ];

        bool canSwap = balanceOf(address(this)) >= threshold;

        if (canSwap && !isSwapping && !status[2] && (!status[0] || !status[1]))
            swapForStability();

        if (status[0] || status[1]) {
            super._transfer(from, to, amount);
        } else {
            if (status[2])
                // is BUY
                tax = (amount * buyFee) / 100;
            else if (status[3])
                // is SELL
                tax = (amount * sellFee) / 100;

            if (tax > 0) {
                amount -= tax;
                super._transfer(from, address(this), tax);

                uint wadingAmount = (tax * wadingDistribution) / 10;
                if (wadingAmount > 0) wadingPool.addRewards(wadingAmount);
            }
            super._transfer(from, to, amount);
        }
    }
}
