// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPeg {
    //-----------------------------------------------
    // Enums
    //-----------------------------------------------
    enum PegState {
        RECOVERY,
        UNDERPEG,
        BELOWPEG,
        ABOVEPEG,
        OVERPEG,
        EXPANSION
    }
}

interface IBalancer is IPeg {
    //-----------------------------------------------
    // Enums
    //-----------------------------------------------
    enum CollateralRange {
        TOO_LOW,
        UNDER_RANGE,
        IN_RANGE0,
        IN_RANGE1,
        IN_RANGE2,
        ABOVE_RANGE
    }
    //-----------------------------------------------
    // Structs
    //-----------------------------------------------
    struct TaxStructure {
        uint buyTax;
        uint sellTax;
        uint transferTax;
    }

    //-----------------------------------------------
    // Events
    //-----------------------------------------------
    event PegStatusChange(PegState indexed _prev, PegState indexed _new);

    //-----------------------------------------------
    // Functions
    //-----------------------------------------------
    /**
     * @notice updates Peg state based on current price from selected LPs (POL and 3rd Party)
     * @param _newState The new peg status after end of epoch
     * @dev this should ONLY be called by ORACLE on an epoch update
     *      - Each PegState Change has a set of standard functionalities
     *      - on EXPANSION Seignorage Fees are given to the Conclave address
     */
    function setPegStatus(PegState _newState) external;

    /**
     * @notice Adds collateral and creates NUSD
     * @param _token Token address of collateral being added
     * @param amount amount to tokens to add as collateral
     * @dev This function can be toggled on and off based on current peg state
     */
    function addCollateral(address _token, uint amount) external;

    /**
     * @notice Redeems NUSD for collateral
     * @param nusdAmount The amount of NUSD to burn in exchange for collateral token
     * @param _preferredToken Collateral token to receive
     * @dev if there is not enough _preferredToken to return, revert
     */
    function redeemCollateral(
        uint nusdAmount,
        address _preferredToken
    ) external;

    /**
     * Issue bonds to help repeg the price
     * @param nusdAmount amount of NUSD to burn in exchange for BONDS
     * @dev Bond issuance is only available when PEG status is in RECOVERY mode
     */
    function issueBonds(uint nusdAmount) external;

    /**
     * Redeem Bonds for NUSD or NSH
     * @param bondAmount Amount of bonds to redeem in exchange of NUSD and/or NSH
     * @dev to determine what bonds are redeemed for, it depends on the current PegStatus
     */
    function redeemBonds(uint bondAmount) external;

    /**
     * Set the oracle to listen to for peg updates
     * @param _newOracle the address of the new oracle
     * @dev if no oracle has been set, the Owner address should be able to set the new oracle
     */
    function setOracle(address _newOracle) external;

    //-----------------------------------------------
    // VIEW Functions
    //-----------------------------------------------
    function getTaxes(
        PegState _peg,
        CollateralRange _range
    ) external view returns (TaxStructure memory);
}
