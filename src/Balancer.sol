// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./interface/IBalancer.sol";
import "./interface/IExtendedERC20.sol";
import "openzeppelin/access/Ownable.sol";

error NebulaBalancer__NotOracle();

abstract contract NebulaBalancer is IBalancer, Ownable {
    //-----------------------------------------------
    // State Variables
    //-----------------------------------------------
    // Each pegState and collateralRange dictates a unique tax structrure
    mapping(PegState _pegState => mapping(CollateralRange _currentRange => TaxStructure _pegTax))
        private taxStructures;

    IExtendedERC20 public immutable nusd;
    IExtendedERC20 public immutable nsh;
    address public oracle;
    PegState public currentPeg;
    CollateralRange public currentCollateralRange;

    //-----------------------------------------------
    // Modifiers
    //-----------------------------------------------
    modifier onlyOracle() {
        if (msg.sender != oracle) revert NebulaBalancer__NotOracle();
        _;
    }

    //-----------------------------------------------
    // Constructor
    //-----------------------------------------------
    constructor(address _nusd, address _nsh) {
        nusd = IExtendedERC20(_nusd);
        nsh = IExtendedERC20(_nsh);
    }

    //-----------------------------------------------
    // External Functions
    //-----------------------------------------------
    function setPegStatus(PegState newState) external onlyOracle {}

    // OWNER SETTER FUNCTIONS
    function setOracle(address _newOracle) external {
        if (oracle == address(0))
            if (msg.sender != owner()) revert NebulaBalancer__NotOracle();
            else if (msg.sender != oracle) revert NebulaBalancer__NotOracle();
        oracle = _newOracle;
    }

    //-----------------------------------------------
    // Public Functions
    //-----------------------------------------------
    //-----------------------------------------------
    // Internal Functions
    //-----------------------------------------------
    /**
     * Sets the current collateral range.
     * @param _newRange The collateral range to enter in effect
     * @dev this would update the taxes for both tokens.
     */
    function setCollateralRange(CollateralRange _newRange) internal {}
    //-----------------------------------------------
    // Private Functions
    //-----------------------------------------------
    //-----------------------------------------------
    // External View & Pure Functions
    //-----------------------------------------------
    //-----------------------------------------------
    // Public View & Pure Functions
    //-----------------------------------------------
    //-----------------------------------------------
    // Internal View & Pure Functions
    //-----------------------------------------------
    //-----------------------------------------------
    // Private View & Pure Functions
    //-----------------------------------------------
    /// mints NUSD and NSH depending on stuff
    // function to mint rebates % of NSH
    // function to set the max rebates minted this epoch
    // set the current EPOCH STATE
    // check current PCR state
    //    PCR is NUSD / Collateral available
    // NUSD burns will mint a rebate of NSH on specific scenarios
    //   user will select collateral to receive based on PCR amounts.
    // Bond issuance and burning (redemption)
    // Seignorage issuance
}
