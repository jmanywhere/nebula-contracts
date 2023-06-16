// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

//-------------------------------------
//    IMPORTS
//-------------------------------------
import "@solmate/tokens/ERC721.sol";
import "@solmate/auth/Owned.sol";

//-------------------------------------
//    Errors
//-------------------------------------

//-------------------------------------
//    Contract
//-------------------------------------
/**
 * @title Nebuloids NFT
 * @author SemiInvader
 * @notice The Nebuloids NFT contract. This contract is used to mint and manage Nebuloids. Nebuloids will be minted in multiple rounds
 *            First round will be of 85 total Nebuloids. More to come in the future.
 *            For this implementation we'll be adding also ERC2198 support for the NFTs.
 */
contract NebuloidsNFT is ERC721, Owned {
    struct RoundId {
        string uri;
        uint256 start;
        uint256 total;
    }

    mapping(uint256 _id => uint256 _roundId) private roundIdOf;
    mapping(uint256 _roundId => RoundId _round) public rounds;
    uint public currentRound;
    string private hiddenURI;

    constructor(
        string memory _hiddenUri
    ) ERC721("Nebuloids", "NEB") Owned(msg.sender) {
        hiddenURI = _hiddenUri;
        currentRound = 1;
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        uint256 _roundId = roundIdOf[id];
        if (_roundId == 0 || bytes(rounds[_roundId].uri).length == 0) {
            return hiddenURI;
        }
        return rounds[_roundId].uri;
    }
}
