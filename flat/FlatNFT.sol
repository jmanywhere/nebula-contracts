// SPDX-License-FLATTEN-SUPPRESS-WARNING-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

/// @notice Simple single owner authorization mixin.
/// @author Solmate (https://github.com/transmissions11/solmate/blob/main/src/auth/Owned.sol)
abstract contract Owned {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event OwnershipTransferred(address indexed user, address indexed newOwner);

    /*//////////////////////////////////////////////////////////////
                            OWNERSHIP STORAGE
    //////////////////////////////////////////////////////////////*/

    address public owner;

    modifier onlyOwner() virtual {
        require(msg.sender == owner, "UNAUTHORIZED");

        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner) {
        owner = _owner;

        emit OwnershipTransferred(address(0), _owner);
    }

    /*//////////////////////////////////////////////////////////////
                             OWNERSHIP LOGIC
    //////////////////////////////////////////////////////////////*/

    function transferOwnership(address newOwner) public virtual onlyOwner {
        owner = newOwner;

        emit OwnershipTransferred(msg.sender, newOwner);
    }
}

// SPDX-License-FLATTEN-SUPPRESS-WARNING-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

/// @notice Modern, minimalist, and gas efficient ERC-721 implementation.
/// @author Solmate (https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC721.sol)
abstract contract ERC721 {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(
        address indexed from,
        address indexed to,
        uint256 indexed id
    );

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 indexed id
    );

    event ApprovalForAll(
        address indexed owner,
        address indexed operator,
        bool approved
    );

    /*//////////////////////////////////////////////////////////////
                         METADATA STORAGE/LOGIC
    //////////////////////////////////////////////////////////////*/

    string public name;

    string public symbol;

    function tokenURI(uint256 id) public view virtual returns (string memory);

    /*//////////////////////////////////////////////////////////////
                      ERC721 BALANCE/OWNER STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint256 => address) internal _ownerOf;

    mapping(address => uint256) internal _balanceOf;

    function ownerOf(uint256 id) public view virtual returns (address owner) {
        require((owner = _ownerOf[id]) != address(0), "NOT_MINTED");
    }

    function balanceOf(address owner) public view virtual returns (uint256) {
        require(owner != address(0), "ZERO_ADDRESS");

        return _balanceOf[owner];
    }

    /*//////////////////////////////////////////////////////////////
                         ERC721 APPROVAL STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint256 => address) public getApproved;

    mapping(address => mapping(address => bool)) public isApprovedForAll;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    /*//////////////////////////////////////////////////////////////
                              ERC721 LOGIC
    //////////////////////////////////////////////////////////////*/

    function approve(address spender, uint256 id) public virtual {
        address owner = _ownerOf[id];

        require(
            msg.sender == owner || isApprovedForAll[owner][msg.sender],
            "NOT_AUTHORIZED"
        );

        getApproved[id] = spender;

        emit Approval(owner, spender, id);
    }

    function setApprovalForAll(address operator, bool approved) public virtual {
        isApprovedForAll[msg.sender][operator] = approved;

        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(address from, address to, uint256 id) public virtual {
        require(from == _ownerOf[id], "WRONG_FROM");

        require(to != address(0), "INVALID_RECIPIENT");

        require(
            msg.sender == from ||
                isApprovedForAll[from][msg.sender] ||
                msg.sender == getApproved[id],
            "NOT_AUTHORIZED"
        );

        // Underflow of the sender's balance is impossible because we check for
        // ownership above and the recipient's balance can't realistically overflow.
        unchecked {
            _balanceOf[from]--;

            _balanceOf[to]++;
        }

        _ownerOf[id] = to;

        delete getApproved[id];

        emit Transfer(from, to, id);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id
    ) public virtual {
        transferFrom(from, to, id);

        require(
            to.code.length == 0 ||
                ERC721TokenReceiver(to).onERC721Received(
                    msg.sender,
                    from,
                    id,
                    ""
                ) ==
                ERC721TokenReceiver.onERC721Received.selector,
            "UNSAFE_RECIPIENT"
        );
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        bytes calldata data
    ) public virtual {
        transferFrom(from, to, id);

        require(
            to.code.length == 0 ||
                ERC721TokenReceiver(to).onERC721Received(
                    msg.sender,
                    from,
                    id,
                    data
                ) ==
                ERC721TokenReceiver.onERC721Received.selector,
            "UNSAFE_RECIPIENT"
        );
    }

    /*//////////////////////////////////////////////////////////////
                              ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC165 Interface ID for ERC165
            interfaceId == 0x80ac58cd || // ERC165 Interface ID for ERC721
            interfaceId == 0x5b5e139f; // ERC165 Interface ID for ERC721Metadata
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _mint(address to, uint256 id) internal virtual {
        require(to != address(0), "INVALID_RECIPIENT");

        require(_ownerOf[id] == address(0), "ALREADY_MINTED");

        // Counter overflow is incredibly unrealistic.
        unchecked {
            _balanceOf[to]++;
        }

        _ownerOf[id] = to;

        emit Transfer(address(0), to, id);
    }

    function _burn(uint256 id) internal virtual {
        address owner = _ownerOf[id];

        require(owner != address(0), "NOT_MINTED");

        // Ownership check above ensures no underflow.
        unchecked {
            _balanceOf[owner]--;
        }

        delete _ownerOf[id];

        delete getApproved[id];

        emit Transfer(owner, address(0), id);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL SAFE MINT LOGIC
    //////////////////////////////////////////////////////////////*/

    function _safeMint(address to, uint256 id) internal virtual {
        _mint(to, id);

        require(
            to.code.length == 0 ||
                ERC721TokenReceiver(to).onERC721Received(
                    msg.sender,
                    address(0),
                    id,
                    ""
                ) ==
                ERC721TokenReceiver.onERC721Received.selector,
            "UNSAFE_RECIPIENT"
        );
    }

    function _safeMint(
        address to,
        uint256 id,
        bytes memory data
    ) internal virtual {
        _mint(to, id);

        require(
            to.code.length == 0 ||
                ERC721TokenReceiver(to).onERC721Received(
                    msg.sender,
                    address(0),
                    id,
                    data
                ) ==
                ERC721TokenReceiver.onERC721Received.selector,
            "UNSAFE_RECIPIENT"
        );
    }
}

/// @notice A generic interface for a contract which properly accepts ERC721 tokens.
/// @author Solmate (https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC721.sol)
abstract contract ERC721TokenReceiver {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external virtual returns (bytes4) {
        return ERC721TokenReceiver.onERC721Received.selector;
    }
}

// SPDX-License-FLATTEN-SUPPRESS-WARNING-Identifier: MIT
pragma solidity >=0.8.0;

/// @notice Efficient library for creating string representations of integers.
/// @author Solmate (https://github.com/transmissions11/solmate/blob/main/src/utils/LibString.sol)
/// @author Modified from Solady (https://github.com/Vectorized/solady/blob/main/src/utils/LibString.sol)
library LibString {
    function toString(int256 value) internal pure returns (string memory str) {
        if (value >= 0) return toString(uint256(value));

        unchecked {
            str = toString(uint256(-value));

            /// @solidity memory-safe-assembly
            assembly {
                // Note: This is only safe because we over-allocate memory
                // and write the string from right to left in toString(uint256),
                // and thus can be sure that sub(str, 1) is an unused memory location.

                let length := mload(str) // Load the string length.
                // Put the - character at the start of the string contents.
                mstore(str, 45) // 45 is the ASCII code for the - character.
                str := sub(str, 1) // Move back the string pointer by a byte.
                mstore(str, add(length, 1)) // Update the string length.
            }
        }
    }

    function toString(uint256 value) internal pure returns (string memory str) {
        /// @solidity memory-safe-assembly
        assembly {
            // The maximum value of a uint256 contains 78 digits (1 byte per digit), but we allocate 160 bytes
            // to keep the free memory pointer word aligned. We'll need 1 word for the length, 1 word for the
            // trailing zeros padding, and 3 other words for a max of 78 digits. In total: 5 * 32 = 160 bytes.
            let newFreeMemoryPointer := add(mload(0x40), 160)

            // Update the free memory pointer to avoid overriding our string.
            mstore(0x40, newFreeMemoryPointer)

            // Assign str to the end of the zone of newly allocated memory.
            str := sub(newFreeMemoryPointer, 32)

            // Clean the last word of memory it may not be overwritten.
            mstore(str, 0)

            // Cache the end of the memory to calculate the length later.
            let end := str

            // We write the string from rightmost digit to leftmost digit.
            // The following is essentially a do-while loop that also handles the zero case.
            // prettier-ignore
            for { let temp := value } 1 {} {
                // Move the pointer 1 byte to the left.
                str := sub(str, 1)

                // Write the character to the pointer.
                // The ASCII index of the '0' character is 48.
                mstore8(str, add(48, mod(temp, 10)))

                // Keep dividing temp until zero.
                temp := div(temp, 10)

                 // prettier-ignore
                if iszero(temp) { break }
            }

            // Compute and cache the final total length of the string.
            let length := sub(end, str)

            // Move the pointer 32 bytes leftwards to make room for the length.
            str := sub(str, 32)

            // Store the string's length at the start of memory allocated for our string.
            mstore(str, length)
        }
    }
}

// SPDX-License-Identifier: MIT

//-------------------------------------
//    Version
//-------------------------------------
pragma solidity 0.8.20;

/**
 * @title Nebuloids NFT
 * @author SemiInvader
 * @notice The Nebuloids NFT contract. This contract is used to mint and manage Nebuloids. Nebuloids will be minted in multiple rounds
 *            First round will be of 85 total Nebuloids. More to come in the future.
 *            For this implementation we'll be adding also ERC2198 support for the NFTs.
 */
// hidden image ipfs://bafybeid5k6qkzb4k2wdqg7ctyp7hrd3dhwrwc7rv3opczxnasahqwb3jea

//-------------------------------------
//    IMPORTS
//-------------------------------------
// import "@solmate/tokens/ERC721.sol";
// import "@solmate/auth/Owned.sol";
// import "@solmate/utils/LibString.sol";

//-------------------------------------
//    Errors
//-------------------------------------
/// @notice Error codes for the Nebuloids NFT contract
/// @param roundId the id of the round that failed
error Nebuloids__URIExists(uint256 roundId);
/// @notice Mint Amount was exceeded
error Nebuloids__MaxMintExceeded();
/// @notice Insufficient funds to mint
error Nebuloids__InsufficientFunds();
/// @notice Max amount of NFTs for the round was exceeded
error Nebuloids__MaxRoundMintExceeded();
/// @notice Reentrant call
error Nebuloids__Reentrant();
/// @notice Round has not ended
error Nebuloids__RoundNotEnded();
error Nebuloids__FailToClaimFunds();

//-------------------------------------
//    Contract
//-------------------------------------
contract NebuloidsNFT is ERC721, Owned {
    using LibString for uint256;
    //-------------------------------------
    //    Type Declarations
    //-------------------------------------
    struct RoundId {
        string uri;
        uint256 start;
        uint256 total;
        uint256 minted;
        uint256 price;
    }

    //-------------------------------------
    //    State Variables
    //-------------------------------------
    mapping(uint256 _id => uint256 _roundId) public roundIdOf;
    mapping(uint256 _roundId => RoundId _round) public rounds;
    // A user can only mint a max of 5 NFTs per round
    mapping(address => mapping(uint256 => uint8)) public userMints;
    string private hiddenURI;
    address private royaltyReceiver;
    uint public currentRound;
    uint public totalSupply;
    uint private reentrant = 1;
    uint private royaltyFee = 7;
    uint private constant ROYALTY_BASE = 100;

    uint8 public constant MAX_MINTS_PER_ROUND = 5;

    //-------------------------------------
    //    Modifers
    //-------------------------------------
    modifier reentrancyGuard() {
        if (reentrant == 2) revert Nebuloids__Reentrant();
        reentrant = 2;
        _;
        reentrant = 1;
    }

    //-------------------------------------
    //    Constructor
    //-------------------------------------
    constructor(
        string memory _hiddenUri
    ) ERC721("Nebuloids", "NEB") Owned(msg.sender) {
        hiddenURI = _hiddenUri;
    }

    //-----------------------------------------
    //    External Functions
    //-----------------------------------------
    function mint(uint256 amount) external payable reentrancyGuard {
        if (
            msg.sender != owner &&
            (amount > MAX_MINTS_PER_ROUND ||
                userMints[msg.sender][currentRound] + amount >
                MAX_MINTS_PER_ROUND ||
                amount == 0)
        ) revert Nebuloids__MaxMintExceeded(); // Can't mint more than max

        RoundId storage round = rounds[currentRound];
        if (msg.sender != owner) {
            uint toCollect = round.price * amount;

            if (msg.value < toCollect) revert Nebuloids__InsufficientFunds();
        }
        if (round.minted + amount > round.total)
            revert Nebuloids__MaxRoundMintExceeded();

        for (uint i = 0; i < amount; i++) {
            uint256 id = round.start + round.minted + i;
            roundIdOf[id] = currentRound;

            _safeMint(msg.sender, id);
        }
        totalSupply += amount;
        // check that amount is added to the minting reward
        userMints[msg.sender][currentRound] += uint8(amount);
        round.minted += amount;
    }

    function startRound(
        uint nftAmount,
        uint price,
        string memory uri
    ) external onlyOwner {
        if (rounds[currentRound].minted != rounds[currentRound].total)
            revert Nebuloids__RoundNotEnded();
        RoundId memory round = RoundId({
            uri: uri,
            start: totalSupply + 1,
            total: nftAmount,
            minted: 0,
            price: price
        });
        currentRound++;
        rounds[currentRound] = round;
    }

    function setUri(uint256 roundId, string memory uri) external onlyOwner {
        if (bytes(rounds[roundId].uri).length != 0)
            revert Nebuloids__URIExists(roundId);
        rounds[roundId].uri = uri;
    }

    function claimFunds() external onlyOwner {
        (bool succ, ) = payable(msg.sender).call{value: address(this).balance}(
            ""
        );
        if (!succ) revert Nebuloids__FailToClaimFunds();
    }

    function setRoyaltyReceiver(address _royaltyReceiver) external onlyOwner {
        royaltyReceiver = _royaltyReceiver;
    }

    //-----------------------------------------
    //    Public Functions
    //-----------------------------------------
    //-----------------------------------------
    //    External and Public View Functions
    //-----------------------------------------
    function tokenURI(uint256 id) public view override returns (string memory) {
        uint256 _roundId = roundIdOf[id];
        if (_roundId == 0 || bytes(rounds[_roundId].uri).length == 0) {
            return hiddenURI;
        }
        return string(abi.encodePacked(rounds[_roundId].uri, id.toString()));
    }

    /**
     *
     * @param interfaceId the id of the interface to check
     * @return true if the interface is supported, false otherwise
     * @dev added the ERC2981 interface
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == 0x2a55205a || super.supportsInterface(interfaceId);
    }

    /// @notice Called with the sale price to determine how much royalty
    //          is owed and to whom.
    /// @param _tokenId - the NFT asset queried for royalty information
    /// @param _salePrice - the sale price of the NFT asset specified by _tokenId
    /// @return receiver - address of who should be sent the royalty payment
    /// @return royaltyAmount - the royalty payment amount for _salePrice
    function royaltyInfo(
        uint256 _tokenId,
        uint256 _salePrice
    ) external view returns (address receiver, uint256 royaltyAmount) {
        _tokenId; // silence unused variable warning
        // all IDS are the same royalty
        if (royaltyReceiver == address(0)) receiver = owner;
        else receiver = royaltyReceiver;

        royaltyAmount = (_salePrice * royaltyFee) / ROYALTY_BASE;
    }
}
