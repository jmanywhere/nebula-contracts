// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "openzeppelin/access/AccessControl.sol";
import "openzeppelin/token/ERC20/ERC20.sol";

//-----------------------------------------------
// ERRORS
//-----------------------------------------------
error NSH__Insufficient_Allowance();

contract NSH is ERC20, AccessControl {
    //-----------------------------------------------
    // State Variables
    //-----------------------------------------------
    bytes32 private constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 private constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");
    mapping(address => bool) private s_lpAddresses;
    mapping(address => bool) private s_excludeFromFee;

    uint private s_buyFee;
    uint private s_sellFee;
    uint private s_transferFee;
    uint public constant MAX_SUPPLY = 10_000_000_000 ether;
    uint public constant PRE_MINT = 1_500_000_000 ether;
    uint public sellThreshold;
    address public feeManager;

    // Mint only by access and BURN for everyone
    // Needs to have a mapping of LPs to check and add taxes to it.

    //-----------------------------------------------
    // Events
    //-----------------------------------------------
    event SetBuyFee(address indexed caller, uint _prevFee, uint _newFee);
    event SetSellFee(address indexed caller, uint _prevFee, uint _newFee);
    event SetTxFee(address indexed caller, uint _prevFee, uint _newFee);
    event SetFeeManager(address prevManager, address newManager);

    //-----------------------------------------------
    // Constructor
    //-----------------------------------------------
    constructor() ERC20("Nebula Shard", "NSH") {
        _mint(msg.sender, PRE_MINT);

        // Setup admin and fee manager roles
        grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        grantRole(FEE_MANAGER_ROLE, msg.sender);
    }

    //-----------------------------------------------
    // External Functions
    //-----------------------------------------------
    function mint(
        address _user,
        uint256 _amount
    ) external onlyRole(MINTER_ROLE) {
        _mint(_user, _amount);
    }

    function burn(uint _amount) external {
        _burn(msg.sender, _amount);
    }

    function burnFrom(address _user, uint _amount) external {
        if (msg.sender != _user) {
            uint256 currentAllowance = allowance(_user, msg.sender);
            if (currentAllowance < _amount)
                revert NSH__Insufficient_Allowance();
            _approve(_user, msg.sender, currentAllowance - _amount);
        }
        _burn(_user, _amount);
    }

    function setBuyFees(uint _buyFee) external onlyRole(FEE_MANAGER_ROLE) {
        require(_buyFee <= 10, "NSH: Buy fee cannot be more than 10%");
        emit SetBuyFee(msg.sender, s_buyFee, _buyFee);
        s_buyFee = _buyFee;
    }

    function setSellFees(uint _sellFee) external onlyRole(FEE_MANAGER_ROLE) {
        require(_sellFee <= 10, "NSH: Buy fee cannot be more than 10%");
        emit SetSellFee(msg.sender, s_sellFee, _sellFee);
        s_sellFee = _sellFee;
    }

    function setTransferFees(
        uint _transferFee
    ) external onlyRole(FEE_MANAGER_ROLE) {
        require(_transferFee <= 10, "NSH: Buy fee cannot be more than 10%");
        emit SetTxFee(msg.sender, s_transferFee, _transferFee);
        s_transferFee = _transferFee;
    }

    function setFeeManager(
        address _newManager
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit SetFeeManager(feeManager, _newManager);
        revokeRole(FEE_MANAGER_ROLE, feeManager);
        feeManager = _newManager;
        grantRole(FEE_MANAGER_ROLE, _newManager);
    }

    //-----------------------------------------------
    // Public Functions
    //-----------------------------------------------
    //-----------------------------------------------
    // Internal & Private Functions
    //-----------------------------------------------
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
            fee = (amount * s_buyFee) / 100;
        } else if (lpAndExcluded[1] && lpAndExcluded[2]) {
            fee = (amount * s_sellFee) / 100;
        } else if (lpAndExcluded[2] && lpAndExcluded[3]) {
            fee = (amount * s_transferFee) / 100;
        }

        amount -= fee;
        if (fee > 0) super._transfer(sender, feeManager, fee);

        super._transfer(sender, recipient, amount);
    }
    //-----------------------------------------------
    // Private & Internal View Functions
    //-----------------------------------------------
    //-----------------------------------------------
    // External & Public View Functions
    //-----------------------------------------------
}
