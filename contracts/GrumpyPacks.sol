// SPDX-License-Identifier: MIT


pragma solidity ^0.8.4;

import "./IERC721ABurnable.sol";
import "./ERC721AQueryable.sol";
import "./openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./openzeppelin/contracts/security/Pausable.sol";
import "./openzeppelin/contracts/access/Ownable.sol";

contract GrumpyPacks is ERC721AQueryable, IERC721ABurnable, Ownable, Pausable, ReentrancyGuard {

    event PermanentURI(string _value, uint256 indexed _id);

    // ============================================================= //
    //                           CONSTANTS                           //
    // ============================================================= //


    address private _authorizedContract;
    address private _admin;
    uint256 public _maxMintPerWallet = 250;
    uint256 public _maxSupply = 250;
    uint256 public PRICE = 0.05 ether;
    bool private _maxSupplyLocked; 
    bool public _baseURILocked;
    string public _normalUri;
    mapping (uint256 => string) customURIs;


    // ============================================================= //
    //                         Constructor                           //
    // ============================================================= //

    // Needs new Metadata Module - 1 URI to rule them all!
    constructor(
        string memory normalUri,
        address admin)
    ERC721A("GrumpyPacks", "GrumpyPacks") {
        _admin = admin;
        _safeMint(msg.sender, 1);
        _pause();
        _normalUri = normalUri;
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
    //                       Control Panel                           //
    // ============================================================= //

    //Withdraw                                                                // Needs to be set to Splits contract
    function withdrawMoney(address to) external onlyOwnerOrAdmin {
        (bool success, ) = to.call{value: address(this).balance}("");
        require(success, "Transfer failed.");
    }

     // OpenSea metadata initialization
    function contractURI() public pure returns (string memory) {
        return "<contract URI>"; // Needs final Contract MetaData
    }

     // Locks base token URI forever and emits PermanentURI for marketplaces (e.g. OpenSea)
    function lockBaseURI() external onlyOwnerOrAdmin {
        _baseURILocked = true;
        for (uint256 i = 0; i < totalSupply(); i++) {
            emit PermanentURI(tokenURI(i), i);
        }
    }

    function setNewTokenURI(uint256 typeOfURI, uint256 tokenId, string calldata newURI) external onlyOwnerOrAdmin{
        if(typeOfURI == 0) 
            _normalUri = newURI;
        else 
            customURIs[tokenId] = newURI;
    }

    function tokenURI(uint256 tokenId) public view virtual override(ERC721A, IERC721A) returns (string memory) {
        return (bytes(customURIs[tokenId]).length == 0) ? _normalUri : customURIs[tokenId];
    }

    // ============================================================= //
    //                       Mint Fuctions                           //
    // ============================================================= //

    function mint(uint256 quantity)
        external
        payable
        nonReentrant
        callerIsUser
        whenNotPaused
    {
        uint256 price = PRICE * quantity;
        require(msg.value >= price, "Not enough ETH");
        require(_numberMinted(msg.sender) + quantity <= _maxMintPerWallet, "Quantity exceeds wallet limit");
        require(totalSupply() + quantity <= _maxSupply, "Quantity exceeds supply");

        _safeMint(msg.sender, quantity);

               // refund excess ETH
        if (msg.value > price) {
            payable(msg.sender).transfer(msg.value - price);
        }
    }
    
    // Ownermint/Airdrop faciliator 
    function ownerMint(address to, uint256 quantity) external onlyOwnerOrAdmin {
        require(totalSupply() + quantity <= _maxSupply, "Quantity exceeds supply");
        _safeMint(to, quantity);
    }

    // ============================================================= //
    //                         Mint Controls                         //
    // ============================================================= //

    // Pauses the mint process
    function pause() external onlyOwnerOrAdmin {
        _pause();
    }

    // Unpauses the mint process
    function unpause() external onlyOwnerOrAdmin {
        _unpause();
    }

    // Adjust the mint price //
    function setPrice(uint256 newPrice) external onlyOwnerOrAdmin {
        PRICE = newPrice;
    }


    // Adjustable limit for mints per person.
    function setMaxMintPerWallet(uint256 quantity) external onlyOwnerOrAdmin {
        _maxMintPerWallet = quantity;
    }

    // ============================================================= //
    //                       Supply Controls                         //
    // ============================================================= //

    // Max Supply Control
    function setMaxSupply(uint256 supply) external onlyOwnerOrAdmin {
        require(!_maxSupplyLocked, "Max supply is locked");
        _maxSupply = supply;
    }

    // Locks maximum supply forever
    function lockMaxSupply() external onlyOwnerOrAdmin {
        _maxSupplyLocked = true;
    }

   
    // Only the owner of the token and its approved operators, and the authorized contract
    // can call this function.
    function burn(uint256 tokenId) public virtual override {
        // Avoid unnecessary approvals for the authorized contract
        bool approvalCheck = msg.sender != _authorizedContract;
        _burn(tokenId, approvalCheck);
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