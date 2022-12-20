// SPDX-License-Identifier: MIT
         


pragma solidity ^0.8.16;

import "./IERC721ABurnable.sol";
import "./ERC721AQueryable.sol";
import "./openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./openzeppelin/contracts/access/Ownable.sol";

contract GrumpyNFTs is ERC721A, ERC721AQueryable, IERC721ABurnable, Ownable, ReentrancyGuard {
    event PermanentURI(string _value, uint256 indexed _id);

    // ============================================================= //
    //                           CONSTANTS                           //
    // ============================================================= //


    PackContract private PACK;
    
    uint256 public MAX_SUPPLY = 200;

    bool public openPackPaused;
    bool public contractPaused;
    bool public baseURILocked;
    string private _baseTokenURI;

    address private _burnAuthorizedContract;
    address private _admin;


    // ============================================================= //
    //                         Constructor                           //
    // ============================================================= //

    constructor(
        string memory baseTokenURI,
        address admin,
        address packContract)
    ERC721A("GrumpyNFT", "GrumpyNFT") {
        _admin = admin;
        _baseTokenURI = baseTokenURI;
        openPackPaused = false;
        PACK = PackContract(packContract);
        _safeMint(msg.sender, 1);
    }


    // ============================================================= //
    //                           MODIFIERS                           //
    // ============================================================= //

    modifier callerIsUser() {
        require(tx.origin == msg.sender, "Caller is another contract");
        _;
    }
    
    modifier onlyOwnerOrAdmin() {
        require(msg.sender == owner() || msg.sender == _admin, "Not owner or admin");
        _;
    }


    // ============================================================= //
    //                      Pack Open Mechanics                      //
    // ============================================================= //

    // Starts the migration process of given Grumpy Pack

    function startopenPack(uint256[] memory packIds)
        external
        nonReentrant
        callerIsUser
    {
        require(!openPackPaused && !contractPaused, "Pack opening is paused");


        uint256 i;
        for (i = 0; i < packIds.length;) {
            uint256 packId = packIds[i];
            // check if the msg sender is the owner
            require(PACK.ownerOf(packId) == msg.sender, "You don't own the given Pack");

            // burn pack
            PACK.burn(packId);

            unchecked { i++; }
        }
            // mint contents
             _safeMint(msg.sender, packIds.length * 5); //6 NFTS = 5 still + 1 Video

    }

    function ownerMint(address to, uint256 quantity) external onlyOwnerOrAdmin {
        require(_totalMinted() + quantity <= MAX_SUPPLY, "Quantity exceeds supply");
        _safeMint(to, quantity);
        
    }

    function totalMinted() external view returns (uint256) {
        return _totalMinted();
    }

    // Only the owner of the token and its approved operators, and the authorized contract
    // can call this function.
    function burn(uint256 tokenId) public virtual override {
        // Avoid unnecessary approvals for the authorized contract
        bool approvalCheck = msg.sender != _burnAuthorizedContract;
        _burn(tokenId, approvalCheck);
    }

    // ============================================================= //
    //                          Game Controls                        //
    // ============================================================= //

    function pauseopenPack(bool paused) external onlyOwnerOrAdmin {
        openPackPaused = paused;
    }

    function pauseContract(bool paused) external onlyOwnerOrAdmin {
        contractPaused = paused;
    }

    function _beforeTokenTransfers(
        address /* from */,
        address /* to */,
        uint256 /* startTokenId */,
        uint256 /* quantity */
    ) internal virtual override {
        require(!contractPaused, "Contract is paused");
    }

    // ============================================================= //
    //                        Metadata Controls                      //
    // ============================================================= //

    // Locks base token URI forever and emits PermanentURI for marketplaces (e.g. OpenSea)
    function lockBaseURI() external onlyOwnerOrAdmin {
        baseURILocked = true;
        for (uint256 i = 0; i < _nextTokenId(); i++) {
            if (_exists(i)) {
                emit PermanentURI(tokenURI(i), i);
            }
        }
    }

    function setBaseURI(string calldata newBaseURI) external onlyOwnerOrAdmin {
        require(!baseURILocked, "Base URI is locked");
        _baseTokenURI = newBaseURI;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

        // OpenSea metadata initialization
    function contractURI() public pure returns (string memory) {
        return "<> contract URI";
    }

    // ============================================================= //
    //                     Authorization Controls                    //
    // ============================================================= //

    function setAdmin(address admin) external onlyOwner {
        _admin = admin;
    }
    
    function setPackContract(address addr) external onlyOwnerOrAdmin {
        PACK = PackContract(addr);
    }

    function setBurnAuthorizedContract(address authorizedContract) external onlyOwnerOrAdmin {
        _burnAuthorizedContract = authorizedContract;
    }
    
    function withdrawMoney(address to) external onlyOwnerOrAdmin {
        (bool success, ) = to.call{value: address(this).balance}("");
        require(success, "Transfer failed.");
    }

    // ============================================================= //
    //                      Marketplace Controls                     //
    // ============================================================= //

    // Blocklist
    // Opensea Conduit: 0x643345d57543de56ea95db86ca9b77d4bd8cd7f7
    // Seaport: 0x00000000006c3852cbEf3e08E8dF289169EdE581
    // Looksrare Transfer Manager ERC721 : 0xF8C81f3ae82b6EFC9154c69E3db57fD4da57aB6E
    // Blur.io ExecutionDelegate : 0x00000000000111AbE46ff893f3B2fdF1F759a8A8
    // SudoSwap LSSVMPairEnumerableETH : 0x08CE97807A81896E85841d74FB7E7B065ab3ef05
    // SudoSwap LSSVMPairEnumerableERC20 : 0xD42638863462d2F21bb7D4275d7637eE5d5541eB
    // SudoSwap LSSVMPairMissingEnumerableERC20	: 0x92de3a1511EF22AbCf3526c302159882a4755B22	
    // SudoSwap LSSVMPairMissingEnumerableETH : 0xCd80C916B1194beB48aBF007D0b79a7238436D56	
    // SudoSwap LSSVMPairFactory : 0xb16c1342E617A5B6E4b631EB114483FDB289c0A4
    // NFTX NFTXMarketplaceZap	: 0x0fc584529a2aefa997697fafacba5831fac0c22d
    
    mapping(address => bool) private _marketplaceBlocklist;

    function approve(address to, uint256 tokenId) public virtual override(ERC721A, IERC721A) {
        require(_marketplaceBlocklist[to] == false, "Marketplace is blocked");
        super.approve(to, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) public virtual override(ERC721A, IERC721A) {
        require(_marketplaceBlocklist[operator] == false, "Marketplace is blocked");
        super.setApprovalForAll(operator, approved);
    }

    function blockMarketplace(address addr, bool blocked) public onlyOwnerOrAdmin {
        _marketplaceBlocklist[addr] = blocked;
    }


}

    // ============================================================= //
    //                           Interfaces                          //
    // ============================================================= //

interface PackContract {
    function burn(uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address owner);
}