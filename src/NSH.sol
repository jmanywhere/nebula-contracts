// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "openzeppelin/access/AccessControl.sol";
import "openzeppelin/token/ERC20/ERC20.sol";

//-----------------------------------------------
// ERRORS
//-----------------------------------------------
error NSH__Insufficient_Allowance();
error NSH__OverSupplyMint();

contract NSH is ERC20, AccessControl {
    //-----------------------------------------------
    // State Variables
    //-----------------------------------------------
    bytes32 private constant MINTER_ROLE = keccak256("MINTER_ROLE");
    mapping(address => bool) private s_lpAddresses;
    mapping(address => bool) private s_excludeFromFee;

    uint private constant s_buyFee = 7;
    uint private constant s_sellFee = 7;
    uint private constant s_transferFee = 2;
    uint private constant BASE_PERCENTAGE = 100;
    uint public constant MAX_SUPPLY = 10_000_000_000 ether;
    uint public constant PRE_MINT = 1_500_000_000 ether;
    uint public sellThreshold;
    address public feeManager;

    //-----------------------------------------------
    // Events
    //-----------------------------------------------
    event SetBuyFee(address indexed caller, uint _prevFee, uint _newFee);
    event SetSellFee(address indexed caller, uint _prevFee, uint _newFee);
    event SetTxFee(address indexed caller, uint _prevFee, uint _newFee);
    event SetFeeManager(address prevManager, address newManager);
    event SetLPAddress(address indexed lpAddress, bool status);
    event SetExcludedAddress(address indexed toExclude, bool indexed newStatus);

    //-----------------------------------------------
    // Constructor
    //-----------------------------------------------
    constructor() ERC20("Nebula Stronghold", "NSH") {
        _mint(msg.sender, PRE_MINT);

        // Setup admin and fee manager roles
        grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    //-----------------------------------------------
    // External Functions
    //-----------------------------------------------
    /**
     * @notice Function to MINT tokens to a specified user.
     * @param _user Address to mint tokens to
     * @param _amount Amount of tokens to mint to
     * @dev this can only be called by the MINTER_ROLE
     */
    function mint(
        address _user,
        uint256 _amount
    ) external onlyRole(MINTER_ROLE) {
        if (_amount + totalSupply() > MAX_SUPPLY) revert NSH__OverSupplyMint();
        _mint(_user, _amount);
    }

    /**
     * @notice Burns tokens from the caller. We allow anyone to burn tokens
     * @param _amount Amount of tokens to BURN
     */
    function burn(uint _amount) external {
        _burn(msg.sender, _amount);
    }

    /**
     * @notice Similar to transferFrom, but burns instead of transferring.
     * @param _user User to burn tokens from
     * @param _amount amount of tokens to BURN
     */
    function burnFrom(address _user, uint _amount) external {
        if (msg.sender != _user) {
            uint256 currentAllowance = allowance(_user, msg.sender);
            if (currentAllowance < _amount)
                revert NSH__Insufficient_Allowance();
            _approve(_user, msg.sender, currentAllowance - _amount);
        }
        _burn(_user, _amount);
    }

    /**
     * @notice Only AdminRole can set feeManager who will receive fees
     * @param _newManager set address that will receive Fees
     */
    function setFeeManager(
        address _newManager
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit SetFeeManager(feeManager, _newManager);
        feeManager = _newManager;
    }

    /**
     * @notice Sets an address as LP
     * @param _lpAddress the Address to set as an LP
     * @dev can only set an address as an LP but cannot unset it.
     */
    function setThirdPartyLP(
        address _lpAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!s_lpAddresses[_lpAddress], "Status already set");
        s_lpAddresses[_lpAddress] = true;
        emit SetLPAddress(_lpAddress, true);
    }

    /**
     * @notice sets the exclusion status of certain addresses
     * @param _addressToExclude address to change the exclusion status
     * @param status new exclusion status
     * @dev can only change status and not add same status
     */
    function setAddressAsExcluded(
        address _addressToExclude,
        bool status
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            s_excludeFromFee[_addressToExclude] != status,
            "Status already set"
        );
        s_excludeFromFee[_addressToExclude] = status;
        emit SetExcludedAddress(_addressToExclude, status);
    }

    //-----------------------------------------------
    // Internal & Private Functions
    //-----------------------------------------------
    /**
     * Modify the underlying  token transfer functionality
     * @param sender Address that is sending the tokens
     * @param recipient Address that is receiving the tokens
     * @param amount Amount of tokens to transfer
     * @dev applies a tax and sends it to the fee Manager for usage and distribution.
     */
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override {
        bool[4] memory lpAndExcluded = [
            s_lpAddresses[sender], // is BUY
            s_lpAddresses[recipient], // is Sell
            !s_excludeFromFee[sender], // sender not excluded
            !s_excludeFromFee[recipient] // recipient not excluded
        ];

        uint fee = 0;
        if (lpAndExcluded[0] && lpAndExcluded[3]) {
            fee = (amount * s_buyFee) / BASE_PERCENTAGE;
        } else if (lpAndExcluded[1] && lpAndExcluded[2]) {
            fee = (amount * s_sellFee) / BASE_PERCENTAGE;
        } else if (lpAndExcluded[2] && lpAndExcluded[3]) {
            fee = (amount * s_transferFee) / BASE_PERCENTAGE;
        }

        amount -= fee;
        if (fee > 0) super._transfer(sender, feeManager, fee);

        super._transfer(sender, recipient, amount);
    }

    //-----------------------------------------------
    // External & Public View/Pure Functions
    //-----------------------------------------------
    function isLP(address _addressToCheck) external view returns (bool) {
        return s_lpAddresses[_addressToCheck];
    }

    function isExcludedFromFees(
        address _addressToCheck
    ) external view returns (bool) {
        return s_excludeFromFee[_addressToCheck];
    }

    function getFees() external view returns (uint, uint, uint) {
        return (s_buyFee, s_sellFee, s_transferFee);
    }
}
