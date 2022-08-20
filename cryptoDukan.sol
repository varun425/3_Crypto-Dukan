//SPDX-License-Identifier: cryptoDukan

/****
    cryptoNFTdukan is in 2 parts 
        1) only listing and deslisting 
        -- list any nft for price
        -- buy at listed price
        -- delist 
        -- withdraw profit 
        -- update list
        -- getListed nfts
        2) lazy minting 
        3) royalty 
        4) 721 or 1155     
    */
pragma solidity ^0.8.1;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "https://github.com/abdk-consulting/abdk-libraries-solidity/blob/master/ABDKMath64x64.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract CryptoDukan is ReentrancyGuard {
    using ABDKMath64x64 for uint256;
    //---------errors--------------------------//
    error ZeroValue(uint256 zero);
    error NotApproved(uint256 tokenID);
    error AlreadyListed(uint256 tokenID);
    error NotListed(uint256 tokenID);
    error InterfaceCheckFailed();
    error FalseOwner();

    //---------events--------------------------//
    event ItemListed(
        address indexed nftContractAddress,
        uint256 indexed price,
        uint256 tokenID
    );

    event ItemUpdated(
        address indexed nftContractAddress,
        uint256 indexed price,
        uint256 tokenID
    );

    //---------structs-------------------------//
    struct listedStruct {
        address owner;
        uint256 price;
        uint256 tokenID;
    }

    //---------state-variables-----------------//
    uint256 public totalListedNfts;
    int8 feeNumerator;
    int8 feeDenominator;

    //---------mappings-------------------------//
    mapping(address => mapping(uint256 => listedStruct)) public listedRecords;
    mapping(address => uint256) public checkProfit;

    //---------modifiers-------------------------//
    modifier zero(uint256 _price,address _nftContractAddress) {
        if (_nftContractAddress == address(0) || _price == 0 ) {
            revert ZeroValue(0);
        }
        _;
    }

    modifier isListed(uint256 _tokenID, address _nftContractAddress) {
        if (listedRecords[_nftContractAddress][_tokenID].tokenID != _tokenID) {
            revert NotListed(_tokenID);
        }
        _;
    }

    modifier interfaceCheck(address nftContractAddress) {
        if (!_implementsERC721(nftContractAddress)) {
            revert InterfaceCheckFailed();
        }
        _;
    }

    modifier isAppproved(address _nftContractAddress, uint256 _tokenID) {
        bool res = isApprovedForCryptoDukan(_nftContractAddress, _tokenID);
        if (!res) {
            revert NotApproved(_tokenID);
        }
        _;
    }

    constructor(int8 _feeNumerator, int8 _feeDenominator) {
        feeNumerator = _feeNumerator; // set to 50
        feeDenominator = _feeDenominator; //  set to 1000
    }

    function list(
        address _nftContractAddress,
        uint256 _price,
        uint256 _tokenID
    )
        external
        nonReentrant
        interfaceCheck(_nftContractAddress)
        isAppproved(_nftContractAddress, _tokenID)
        zero(_price,_nftContractAddress)
    {
        if (
            listedRecords[_nftContractAddress][_tokenID].tokenID == _tokenID
        ) {
            revert AlreadyListed(_tokenID);
        }
        emit ItemListed(_nftContractAddress, _price, _tokenID);
        listedStruct storage l = listedRecords[_nftContractAddress][_tokenID];
        l.owner = msg.sender;
        l.price = _price * 1 ether;
        l.tokenID = _tokenID;
        totalListedNfts + 1;
    }

    function isApprovedForCryptoDukan(
        address _nftContractAddress,
        uint _tokenID
    ) public view returns (bool) {
        address to = IERC721(_nftContractAddress).getApproved(_tokenID);
        if (to == address(this)) {
            return true;
        } else {
            return false;
        }
    }

    function _implementsERC721(address _contractAddress)
        internal
        view
        returns (bool)
    {
        return
            IERC165(_contractAddress).supportsInterface(
                type(IERC721).interfaceId
            );
    }

    function buy(address _nftContractAddress, uint256 _tokenID)
        external
        payable
        nonReentrant
        isListed(_tokenID, _nftContractAddress)
        isAppproved(_nftContractAddress, _tokenID)
    {
        listedStruct memory l = listedRecords[_nftContractAddress][_tokenID];
        uint256 listedPrice = l.price;
        address listedItemOwner = l.owner;
        require(msg.value == listedPrice, "out of listed price");
        if (msg.value == 0) {
            revert ZeroValue(0);
        }
        uint256 _ItemPrice = listedRecords[_nftContractAddress][_tokenID].price;
        address owner = listedRecords[_nftContractAddress][_tokenID].owner;
        delist(_nftContractAddress, _tokenID);
        uint256 platformFee = calulcateFee(_ItemPrice);
        checkProfit[listedItemOwner] = msg.value - platformFee;
        IERC721(_nftContractAddress).safeTransferFrom(
            owner,
            msg.sender,
            _tokenID,
            bytes("")
        );
    }

    function delist(address _nftContractAddress, uint256 _tokenID)
        public
        isListed(_tokenID, _nftContractAddress)
        nonReentrant
    {   if(_nftContractAddress == address(0)) revert ZeroValue(0);
        delete listedRecords[_nftContractAddress][_tokenID];
    }

    function calulcateFee(uint256 _ItemPrice) public view returns (uint256) {
        int128 feeRatio = ABDKMath64x64.divi(feeNumerator, feeDenominator);
        uint256 fees = ABDKMath64x64.mulu(feeRatio, _ItemPrice);
        return (fees);
    }

    function updateList(
        address _nftContractAddress,
        uint256 _price,
        uint256 _tokenID
    )
        external
        nonReentrant
        isListed(_tokenID, _nftContractAddress)
        interfaceCheck(_nftContractAddress)
        zero(_price,_nftContractAddress)
    {
        if (IERC721(_nftContractAddress).ownerOf(_tokenID) != msg.sender) 
        revert FalseOwner();
        emit ItemUpdated(_nftContractAddress, _price, _tokenID);
        listedStruct storage l = listedRecords[_nftContractAddress][_tokenID];
        l.owner = msg.sender;
        l.price = _price * 1 ether;
        l.tokenID = _tokenID;
    }

    function checkRoyalty() internal {
        
    }

    function withdraw() external nonReentrant {
        uint256 profit = checkProfit[msg.sender];
        if (profit <= 0) revert ZeroValue(0);
        (bool success, ) = msg.sender.call{value: profit}("");
        require(success, "transfer failed");
    }

    fallback() external {}

    receive() external payable {}
}
