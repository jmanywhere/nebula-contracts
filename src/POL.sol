// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "openzeppelin/access/AccessControlEnumerable.sol";
import "openzeppelin/token/ERC20/extensions/ERC20Burnable.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "./interface/IPOL.sol";
import "./libraries/UQ112x112.sol";

error InvalidArguments();
error InvalidInitialLiquidity();
error ExceedMaxDailySell();
error BelowMinimum(uint256 min, uint256 val);
error AboveMaximum(uint256 max, uint256 val);

contract POLv2 is IPOL, ERC20Burnable, AccessControlEnumerable {
    using SafeERC20 for IERC20Metadata;
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

    IERC20Metadata public immutable tokenA;
    IERC20Metadata public immutable tokenB;

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
        IERC20Metadata _tokenA,
        IERC20Metadata _tokenB,
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
        if (_maxTokenA == 0 || _tokenBAmount == 0 || _minLiquidity == 0)
            revert InvalidArguments();

        uint256 totalLiq = totalSupply();

        //Calculate tokenA amount and liquidity to mint.
        uint256 tokenAAmount;
        if (totalLiq > 0) {
            (liqMinted_, tokenAAmount) = getTokenBToLiquidityInputPrice(
                _tokenBAmount
            );
            if (_maxTokenA < tokenAAmount)
                revert AboveMaximum(_maxTokenA, tokenAAmount);
            if (liqMinted_ < _minLiquidity)
                revert BelowMinimum(_minLiquidity, liqMinted_);
        } else {
            if (
                _tokenBAmount < 10 ** (tokenB.decimals() / 4) ||
                _maxTokenA < 10 ** (tokenA.decimals() / 4) ||
                _maxTokenA / _tokenBAmount > 2 ** 64 ||
                _tokenBAmount / _maxTokenA > 2 ** 64
            ) revert InvalidInitialLiquidity();

            liqMinted_ = _tokenBAmount;
            tokenAAmount = _maxTokenA;
        }

        tokenA.safeTransferFrom(msg.sender, address(this), tokenAAmount);
        tokenB.safeTransferFrom(msg.sender, address(this), _tokenBAmount);

        _mint(msg.sender, liqMinted_);
        _updatePriceAccumulators();
        emit OnAddLiquidity(
            msg.sender,
            liqMinted_,
            _tokenBAmount,
            tokenAAmount
        );
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
        if (_amount == 0 || _minTokenB == 0 || _minTokenA == 0)
            revert InvalidArguments();
        uint256 totalLiquidity = totalSupply();
        uint256 tokenBAmount = (_amount * tokenBReserve()) / totalLiquidity;
        uint256 tokenAAmount = (_amount * tokenAReserve()) / totalLiquidity;
        if (tokenBAmount < _minTokenB)
            revert BelowMinimum(tokenBAmount, _minTokenB);
        if (tokenAAmount < _minTokenA)
            revert BelowMinimum(tokenAAmount, _minTokenA);
        _burn(msg.sender, _amount);
        tokenB.safeTransfer(msg.sender, tokenBAmount);
        tokenA.safeTransfer(msg.sender, tokenAAmount);
        _updatePriceAccumulators();
        emit OnRemoveLiquidity(msg.sender, _amount, tokenBAmount, tokenAAmount);
        return (tokenBAmount, tokenAAmount);
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
        // BUYER IS ALWAYS MSG.SENDER
        if (_tokenBInput > 0)
            _output = _tokenBToTokenA(
                _tokenBInput,
                _minIntout,
                _to,
                msg.sender
            );
        else if (_tokenAOutput > 0)
            _output = _tokenBToTokenA(
                _minIntout,
                _tokenAOutput,
                _to,
                msg.sender
            );
        else if (_tokenAInput > 0)
            _output = _tokenAToTokenB(
                _tokenAInput,
                _minIntout,
                _to,
                msg.sender
            );
        else if (_tokenBOutput > 0)
            _output = _tokenAToTokenB(
                _minIntout,
                _tokenBOutput,
                _to,
                msg.sender
            );
    }

    function _tokenBToTokenA(
        uint256 _tokenB,
        uint256 _min,
        address _to,
        address _buyer
    ) private returns (uint256 tokenA_) {
        (uint256 output, uint256 feeA, uint256 feeB) = outputTokenA(
            _tokenB,
            false,
            !hasRole(WHITELIST_ROLE, _buyer)
        );
        tokenA_ = output;
        tokenB.safeTransferFrom(_buyer, address(this), _tokenB);
        tokenA.safeTransfer(_to, tokenA_);
        if (feeA > 0) {
            tokenA.safeTransfer(treasury, feeA);
        }
        if (feeB > 0) {
            tokenB.safeTransfer(treasury, feeB);
        }
        emit Fee(_buyer, feeA, feeB);
        _updatePriceAccumulators();
        emit Swap(msg.sender, _tokenB, 0, 0, tokenA_);
        if (tokenA_ < _min) revert BelowMinimum(_min, tokenA_);
    }

    function _tokenAToTokenB(
        uint256 _tokenA,
        uint256 _min,
        address _to,
        address _buyer
    ) private returns (uint256 tokenB_) {
        (uint256 output, uint256 feeA, uint256 feeB) = outputTokenB(
            _tokenA,
            false,
            !hasRole(WHITELIST_ROLE, _buyer)
        );
        tokenB_ = output;
        tokenA.safeTransferFrom(_buyer, address(this), _tokenA);
        tokenB.safeTransfer(_to, tokenB_);
        if (feeA > 0) {
            tokenA.safeTransfer(treasury, feeA);
        }
        if (feeB > 0) {
            tokenB.safeTransfer(treasury, feeB);
        }
        emit Fee(_buyer, feeA, feeB);

        _updatePriceAccumulators();
        emit Swap(_buyer, 0, _tokenA, tokenB_, 0);
        if (tokenB_ < _min) revert BelowMinimum(_min, tokenB_);
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
        if (_inputReserve == 0 && _outputReserve == 0)
            revert InvalidArguments();
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
        if (_inputReserve == 0 || _outputReserve == 0)
            revert InvalidArguments();
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
        bool _isDesired,
        bool _withFee
    ) public view returns (uint256 other_, uint256 feeA_, uint256 feeB_) {
        if (_isDesired) {
            feeA_ = _withFee
                ? (_amount * feeRatesBasis[uint256(FEES.tokenABuyFee)]) / BASIS
                : 0;
            other_ = getOutputPrice(
                _amount - feeA_,
                tokenB.balanceOf(address(this)),
                tokenA.balanceOf(address(this))
            );
            feeB_ = _withFee
                ? (other_ * feeRatesBasis[uint256(FEES.tokenBSellFee)]) / BASIS
                : 0;
            other_ += feeB_;
            return (other_, feeA_, feeB_);
        } else {
            feeB_ =
                (_amount * feeRatesBasis[uint256(FEES.tokenBSellFee)]) /
                BASIS;
            other_ = getInputPrice(
                _amount - feeB_,
                tokenB.balanceOf(address(this)),
                tokenA.balanceOf(address(this))
            );
            feeA_ =
                (other_ * feeRatesBasis[uint256(FEES.tokenABuyFee)]) /
                BASIS;
            other_ -= feeA_;
            return (other_, feeA_, feeB_);
        }
    }

    /// @notice same as outputTokenA function except it is based on getting back tokenB and inputting tokenA
    function outputTokenB(
        uint256 _amount,
        bool _isDesired,
        bool _withFee
    ) public view returns (uint256 other_, uint256 feeA_, uint256 feeB_) {
        if (_isDesired) {
            feeB_ = _withFee
                ? (_amount * feeRatesBasis[uint256(FEES.tokenBBuyFee)]) / BASIS
                : 0;
            other_ = getOutputPrice(
                _amount - feeB_,
                tokenA.balanceOf(address(this)),
                tokenB.balanceOf(address(this))
            );
            feeA_ =
                (other_ * feeRatesBasis[uint256(FEES.tokenASellFee)]) /
                BASIS;
            other_ += feeA_;
            return (other_, feeA_, feeB_);
        } else {
            feeA_ =
                (_amount * feeRatesBasis[uint256(FEES.tokenASellFee)]) /
                BASIS;
            other_ = getInputPrice(
                _amount - feeA_,
                tokenA.balanceOf(address(this)),
                tokenB.balanceOf(address(this))
            );
            feeB_ =
                (other_ * feeRatesBasis[uint256(FEES.tokenBBuyFee)]) /
                BASIS;
            other_ -= feeB_;
            return (other_, feeA_, feeB_);
        }
    }

    /// @notice get the _amount of liquidity that would be minted and tokens needed by inputing the _tokenBAmount
    /// @param _tokenBAmount Amount of tokenB tokens to use
    function getTokenBToLiquidityInputPrice(
        uint256 _tokenBAmount
    ) public view returns (uint256 liquidityAmount_, uint256 tokenAAmount_) {
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
    /// @param _tokenAAmount Amount of tokenA tokens to use
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
        uint16 newTotalFees = _tokenABuyFeeBasis +
            _tokenBBuyFeeBasis +
            _tokenASellFeeBasis +
            _tokenBSellFeeBasis;
        if (MAX_FEE < newTotalFees) revert AboveMaximum(MAX_FEE, newTotalFees);
        feeRatesBasis[uint256(FEES.tokenABuyFee)] = _tokenABuyFeeBasis;
        feeRatesBasis[uint256(FEES.tokenBBuyFee)] = _tokenBBuyFeeBasis;
        feeRatesBasis[uint256(FEES.tokenASellFee)] = _tokenASellFeeBasis;
        feeRatesBasis[uint256(FEES.tokenBSellFee)] = _tokenBSellFeeBasis;
    }

    function setMaxSell(uint256 _newMax) external onlyRole(MANAGER_ROLE) {
        maxDailySell = _newMax;
    }

    function setTreasury(address _to) external onlyRole(MANAGER_ROLE) {
        treasury = _to;
    }
}
