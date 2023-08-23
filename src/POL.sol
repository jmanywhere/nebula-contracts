// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "openzeppelin/access/AccessControlEnumerable.sol";
import "openzeppelin/token/ERC20/extensions/ERC20Burnable.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "./interface/IPOL.sol";
import "./libraries/UQ112x112.sol";

contract POLv2 is IPOL, ERC20Burnable, AccessControlEnumerable {
    using SafeERC20 for IERC20;
    using UQ112x112 for uint224;
    enum FEES {
        tokenABuyFee,
        tokenBBuyFee,
        tokenASellFee,
        tokenBSellFee
    }

    //Sell limits only apply to sells on tokenA, not tokenB.
    struct Sells {
        uint256 amountSold;
        uint256 lastSell;
    }
    mapping(address => Sells) public sellTracker;

    IERC20 public immutable tokenA;
    IERC20 public immutable tokenB;

    // ------------------------------------------------
    //           For price oracles
    // ------------------------------------------------
    uint256 public priceACumulativeLast;
    uint256 public priceBCumulativeLast;
    uint32 public blockTimestampLast;

    // ------------------------------------------------
    //           Taxes & Limits
    // ------------------------------------------------

    // Taxes are divided BASIS
    // Indices are from enum FEES
    uint256 public constant BASIS = 10000;
    uint16[4] public feeRatesBasis;
    uint256 public constant MAX_FEE = 3500;
    // MAX daily sells
    uint256 public maxDailySell = 500 ether;

    // ------------------------------------------------
    //           Roles
    // ------------------------------------------------
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant WHITELIST_ROLE = keccak256("WHITELIST_ROLE");
    bytes32 public constant NOSELLLIMIT_ROLE = keccak256("NOSELLLIMIT_ROLE");

    // ------------------------------------------------
    //           Ecosystem addresses
    // ------------------------------------------------
    address public treasury;

    // ------------------------------------------------
    //              LIQUIDITY EVENTS
    // ------------------------------------------------

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

    constructor(
        IERC20 _tokenA,
        IERC20 _tokenB,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        _grantRole(MANAGER_ROLE, msg.sender);
        _setRoleAdmin(WHITELIST_ROLE, MANAGER_ROLE);
        _setRoleAdmin(NOSELLLIMIT_ROLE, MANAGER_ROLE);
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    // ------------------------------------------------
    // IPOL INTERFACE IMPLEMENTATION
    // ------------------------------------------------

    /// @notice Remember to set this contract as excluded from taxes. since transferring tokens burns tokens
    /**
     * @notice Deposit BNB && Tokens (STAKE) at current ratio to mint STOKE tokens.
     * @dev _minLiquidity does nothing when total SWAP supply is 0.
     * @param _minLiquidity Minimum number of STOKE sender will mint if total STAKE supply is greater than 0.
     * @param _maxTokenA Maximum number of tokens deposited. Deposits max _amount if total STOKE supply is 0.
     * @param _tokenBAmount Amount of tokenB to add as liquidity.
     * @return liqMinted_ The _amount of SWAP minted.
     */
    function addLiquidity(
        uint256 _minLiquidity,
        uint256 _maxTokenA,
        uint256 _tokenBAmount
    ) public returns (uint256 liqMinted_) {
        require(_maxTokenA > 0 && _tokenBAmount > 0, "ALIQ1"); //dev: Invalid Arguments
        require(_minLiquidity > 0, "ALIQ2"); //dev: Minimum liquidity to add must be greater than zero

        uint256 resTokenB = tokenBReserve();
        uint256 resTokenA = tokenAReserve();

        tokenB.safeTransferFrom(msg.sender, address(this), _tokenBAmount);

        uint256 totalLiq = totalSupply();
        if (totalLiq > 0) {
            uint256 tokenAAmount = ((_tokenBAmount * resTokenA) / resTokenB) +
                1;
            uint256 liqToMint = (_tokenBAmount * totalLiq) / resTokenB;
            require(
                _maxTokenA >= tokenAAmount && liqToMint >= _minLiquidity,
                "ALIQ4"
            ); //dev: Token amounts mismatch
            tokenA.safeTransferFrom(msg.sender, address(this), tokenAAmount);
            _mint(msg.sender, liqToMint);
            emit OnAddLiquidity(
                msg.sender,
                liqToMint,
                _tokenBAmount,
                tokenAAmount
            );
            liqMinted_ = liqToMint;
        } else {
            require(_tokenBAmount >= 1 ether, "ALIQ6"); // dev: invalid initial _amount of liquidity created
            uint256 initLiq = tokenB.balanceOf(address(this));
            _mint(msg.sender, initLiq);
            tokenA.safeTransferFrom(msg.sender, address(this), _maxTokenA);
            _updatePriceAccumulators();
            emit OnAddLiquidity(msg.sender, initLiq, _tokenBAmount, _maxTokenA);
            liqMinted_ = initLiq;
        }
    }

    /**
     * @dev Burn SWAP tokens to withdraw BNB && Tokens at current ratio.
     * @param _amount Amount of SWAP burned.
     * @param _minTokenB Minimum tokenB withdrawn.
     * @param _minTokenA Minimum Tokens withdrawn.
     * @return The _amount of tokenB && tokenA withdrawn.
     */
    function removeLiquidity(
        uint256 _amount,
        uint256 _minTokenB,
        uint256 _minTokenA
    ) public returns (uint256, uint256) {
        require(_amount > 0 && _minTokenB > 0 && _minTokenA > 0);
        uint256 totalLiquidity = totalSupply();
        require(totalLiquidity > 0);
        uint256 _tokenBAmount = (_amount * tokenB.balanceOf(address(this))) /
            totalLiquidity;
        uint256 tokenAAmount = (_amount * (tokenAReserve())) / totalLiquidity;
        require(
            _tokenBAmount >= _minTokenB && tokenAAmount >= _minTokenA,
            "RLIQ1"
        ); // Not enough tokens to receive
        _burn(msg.sender, _amount);
        tokenB.safeTransfer(msg.sender, _tokenBAmount);
        tokenA.safeTransfer(msg.sender, tokenAAmount);
        _updatePriceAccumulators();
        emit OnRemoveLiquidity(
            msg.sender,
            _amount,
            _tokenBAmount,
            tokenAAmount
        );
        return (_tokenBAmount, tokenAAmount);
    }

    ///@notice swap from one token to the other, please make sure only one value is inputted, as the rest will be ignored
    /// @param _tokenBInput _amount of tokenB tokens to input for swap
    /// @param _tokenAInput _amount of TOKENS to input for swap
    /// @param _tokenBOutput _amount of tokenB tokens to receive
    /// @param _tokenAOutput _amount of TOKENs to receive
    /// @param _minIntout minimum _amount so swap is considered successful
    /// @param _to receiver of the swapped tokens
    /// @return _output _amount of tokens to receive
    function swap(
        uint256 _tokenBInput,
        uint256 _tokenAInput,
        uint256 _tokenBOutput,
        uint256 _tokenAOutput,
        uint256 _minIntout,
        address _to
    ) public returns (uint256 _output) {
        uint256 tokenRes = tokenAReserve();
        uint256 tokenBRes = tokenBReserve();
        // BUYER IS ALWAYS MSG.SENDER
        if (_tokenBInput > 0)
            _output = _tokenBToTokenA(
                _tokenBInput,
                _minIntout,
                _to,
                msg.sender,
                tokenBRes,
                tokenRes
            );
        else if (_tokenAOutput > 0)
            _output = _tokenBToTokenA(
                _minIntout,
                _tokenAOutput,
                _to,
                msg.sender,
                tokenBRes,
                tokenRes
            );
            // TODO CHECK THE NEXT 2
        else if (_tokenAInput > 0)
            _output = _tokenAToTokenB(
                _tokenAInput,
                _minIntout,
                _to,
                msg.sender,
                tokenBRes,
                tokenRes
            );
        else if (_tokenBOutput > 0)
            _output = _tokenAToTokenB(
                _minIntout,
                _tokenBOutput,
                _to,
                msg.sender,
                tokenBRes,
                tokenRes
            );
    }

    function _tokenBToTokenA(
        uint256 _tokenB,
        uint256 _min,
        address _to,
        address _buyer,
        uint256 _resTokenB,
        uint256 _resTokenA
    ) private returns (uint256 tokenA_) {
        tokenB.safeTransferFrom(_buyer, address(this), _tokenB);
        if (hasRole(WHITELIST_ROLE, _buyer)) {
            tokenA_ = getInputPrice(_tokenB, _resTokenB, _resTokenA);
        } else {
            uint256 toTreasuryTokenB = (_tokenB *
                feeRatesBasis[uint256(FEES.tokenBSellFee)]) / BASIS;
            tokenA_ = getInputPrice(
                _tokenB - toTreasuryTokenB,
                _resTokenB,
                _resTokenA
            );
            uint256 toTreasuryTokenA = (tokenA_ *
                feeRatesBasis[uint256(FEES.tokenABuyFee)]) / BASIS;
            tokenA_ -= toTreasuryTokenA;
            if (toTreasuryTokenA > 0) {
                tokenA.safeTransfer(treasury, toTreasuryTokenA);
            }
            if (toTreasuryTokenB > 0) {
                tokenB.safeTransfer(treasury, toTreasuryTokenB);
            }
            emit Fee(_buyer, toTreasuryTokenA, toTreasuryTokenB);
        }
        tokenA.safeTransfer(_to, tokenA_);
        _updatePriceAccumulators();
        emit Swap(msg.sender, _tokenB, 0, 0, tokenA_);
        require(tokenA_ >= _min, "BT1"); // dev: minimum
    }

    function _tokenAToTokenB(
        uint256 _tokenA,
        uint256 _min,
        address _to,
        address _buyer,
        uint256 _resTokenB,
        uint256 _resTokenA
    ) private returns (uint256 tokenB_) {
        // Transfer in tokenA
        tokenA.safeTransferFrom(_buyer, address(this), _tokenA);
        if (hasRole(WHITELIST_ROLE, _buyer)) {
            tokenB_ = getInputPrice(_tokenA, _resTokenA, _resTokenB);
        } else {
            //Check sell limit
            if (!hasRole(NOSELLLIMIT_ROLE, _buyer)) {
                bool prev24hours = block.timestamp -
                    sellTracker[_buyer].lastSell <
                    24 hours;

                if (prev24hours) {
                    require(
                        sellTracker[_buyer].amountSold + _tokenA <=
                            maxDailySell,
                        "TB1"
                    );
                    sellTracker[_buyer].amountSold += _tokenA;
                } else {
                    require(_tokenA <= maxDailySell, "TB2");
                    sellTracker[_buyer].lastSell = block.timestamp;
                    sellTracker[_buyer].amountSold = _tokenA;
                }
            }
            //taxes
            uint256 toTreasuryTokenA = (_tokenA *
                feeRatesBasis[uint256(FEES.tokenASellFee)]) / BASIS;
            tokenB_ = getInputPrice(
                _tokenA - toTreasuryTokenA,
                _resTokenA,
                _resTokenB
            );
            uint256 toTreasuryTokenB = (tokenB_ *
                feeRatesBasis[uint256(FEES.tokenBBuyFee)]) / BASIS;
            tokenB_ -= toTreasuryTokenA;
            if (toTreasuryTokenA > 0) {
                tokenA.safeTransfer(treasury, toTreasuryTokenA);
            }
            if (toTreasuryTokenB > 0) {
                tokenB.safeTransfer(treasury, toTreasuryTokenB);
            }
            emit Fee(_buyer, toTreasuryTokenA, toTreasuryTokenB);
        }

        require(tokenB_ >= _min, "TB3"); // dev: less than minimum
        tokenB.safeTransfer(_to, tokenB_);
        _updatePriceAccumulators();
        emit Swap(_buyer, 0, _tokenA, tokenB_, 0);
    }

    function _updatePriceAccumulators() internal {
        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
        uint32 timeElapsed;
        unchecked {
            // overflow is desired
            timeElapsed = blockTimestamp - blockTimestampLast;
        }
        uint112 tokenARes = uint112(tokenAReserve());
        uint112 tokenBRes = uint112(tokenBReserve());

        if (timeElapsed == 0 || tokenARes == 0 || tokenBRes == 0) return;

        unchecked {
            // * never overflows, and + overflow is desired
            priceACumulativeLast +=
                uint(UQ112x112.encode(tokenBRes).uqdiv(tokenARes)) *
                timeElapsed;
            priceBCumulativeLast +=
                uint(UQ112x112.encode(tokenARes).uqdiv(tokenBRes)) *
                timeElapsed;
        }
        blockTimestampLast = blockTimestamp;
    }

    function tokenAReserve() public view returns (uint256) {
        return tokenA.balanceOf(address(this));
    }

    function tokenBReserve() public view returns (uint256) {
        return tokenB.balanceOf(address(this));
    }

    /**
     * @dev Pricing function for converting between BNB && Tokens without fee when we get the input variable.
     * @param _inputAmount Amount tokenA or tokenB being sold.
     * @param _inputReserve Amount of input tokenA type in exchange reserves.
     * @param _outputReserve Amount of output tokenA type in exchange reserves.
     * @return Amount of Output tokens to receive.
     */
    function getInputPrice(
        uint256 _inputAmount,
        uint256 _inputReserve,
        uint256 _outputReserve
    ) public pure returns (uint256) {
        require(_inputReserve > 0 && _outputReserve > 0, "INVALID_VALUE");
        uint256 numerator = _inputAmount * _outputReserve;
        uint256 denominator = _inputReserve + _inputAmount;
        return numerator / denominator;
    }

    /**
     * @dev Pricing function for converting between BNB && Tokens without fee when we get the output variable.
     * @param _outputAmount Amount of output tokenA type being bought.
     * @param _inputReserve Amount of input tokenA type in exchange reserves.
     * @param _outputReserve Amount of output tokenA type in exchange reserves.
     * @return Amount of input tokenA to receive.
     */
    function getOutputPrice(
        uint256 _outputAmount,
        uint256 _inputReserve,
        uint256 _outputReserve
    ) public pure returns (uint256) {
        require(_inputReserve > 0 && _outputReserve > 0);
        uint256 numerator = _inputReserve * _outputAmount;
        uint256 denominator = (_outputReserve - _outputAmount);
        return (numerator / denominator) + 1;
    }

    /**
     * @dev Pricing function for tokens, depending on the isDesired flag we either get the Input tokenB needed or the output _amount
     * @param _amount the _amount of tokens that will be sent for swap
     * @param _isDesired FLAG - this tells us wether we want the tokenB _amount needed or the TOKENs that will be output
     */
    function outputTokenA(
        uint256 _amount,
        bool _isDesired
    ) public view returns (uint256) {
        if (_isDesired)
            return
                getOutputPrice(
                    _amount,
                    tokenB.balanceOf(address(this)),
                    tokenA.balanceOf(address(this))
                );
        return
            getInputPrice(
                _amount,
                tokenB.balanceOf(address(this)),
                tokenA.balanceOf(address(this))
            );
    }

    /// @notice same as outputTokenA function except it is based on getting back tokenB and inputting tokenA
    function outputTokenB(
        uint256 _amount,
        bool _isDesired
    ) public view returns (uint256) {
        if (_isDesired)
            return
                getOutputPrice(
                    _amount,
                    tokenA.balanceOf(address(this)),
                    tokenB.balanceOf(address(this))
                );
        return
            getInputPrice(
                _amount,
                tokenA.balanceOf(address(this)),
                tokenB.balanceOf(address(this))
            );
    }

    /// @notice get the _amount of liquidity that would be minted and tokens needed by inputing the _tokenBAmount
    /// @param _tokenBAmount Amount of tokenB tokens to use
    function getTokenBToLiquidityInputPrice(
        uint256 _tokenBAmount
    ) external view returns (uint256 liquidityAmount_, uint256 tokenAAmount_) {
        if (_tokenBAmount == 0) return (0, 0);
        uint256 total = totalSupply();
        // +1 is to offset any decimal issues
        (liquidityAmount_, tokenAAmount_) = getLiquidityInputPrice(
            _tokenBAmount,
            tokenBReserve(),
            tokenAReserve(),
            total
        );
    }

    /// @notice get the _amount of liquidity that would be minted and tokens needed by inputing the _tokenBAmount
    /// @param _tokenAAmount Amount of tokenB tokens to use
    function getTokenToLiquidityInputPrice(
        uint256 _tokenAAmount
    ) external view returns (uint256 liquidityAmount_, uint256 tokenBAmount_) {
        if (_tokenAAmount == 0) return (0, 0);
        uint256 total = totalSupply();
        // +1 is to offset any decimal issues
        (liquidityAmount_, tokenBAmount_) = getLiquidityInputPrice(
            _tokenAAmount,
            tokenAReserve(),
            tokenBReserve(),
            total
        );
    }

    function getLiquidityInputPrice(
        uint256 input,
        uint256 inputReserve,
        uint256 otherReserve,
        uint256 currentLiqSupply
    ) public pure returns (uint256 liquidityGen_, uint256 tokensNeeded_) {
        liquidityGen_ = (input * currentLiqSupply) / inputReserve;
        tokensNeeded_ = ((input * otherReserve) / inputReserve) + 1;
    }

    function setTaxes(
        uint16 _tokenABuyFeeBasis,
        uint16 _tokenBBuyFeeBasis,
        uint16 _tokenASellFeeBasis,
        uint16 _tokenBSellFeeBasis
    ) external onlyRole(MANAGER_ROLE) {
        require(
            MAX_FEE <
                _tokenABuyFeeBasis +
                    _tokenBBuyFeeBasis +
                    _tokenASellFeeBasis +
                    _tokenBSellFeeBasis,
            "TX1"
        ); // dev: Max taxes reached
        feeRatesBasis[uint256(FEES.tokenABuyFee)] = _tokenABuyFeeBasis;
        feeRatesBasis[uint256(FEES.tokenBBuyFee)] = _tokenBBuyFeeBasis;
        feeRatesBasis[uint256(FEES.tokenASellFee)] = _tokenASellFeeBasis;
        feeRatesBasis[uint256(FEES.tokenBSellFee)] = _tokenBSellFeeBasis;
    }

    function setMaxSell(uint256 _newMax) external onlyRole(MANAGER_ROLE) {
        maxDailySell = _newMax;
    }
}
