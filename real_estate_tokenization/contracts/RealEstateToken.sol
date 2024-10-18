// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RealEstateToken is ERC721, ERC721URIStorage, ERC721Enumerable, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    struct Property {
        uint256 tokenId;
        string propertyAddress;
        uint256 totalShares;
        uint256 availableShares;
        uint256 pricePerShare;
        uint256 monthlyRentalIncome;
        uint256 lastAccumulationTimestamp;
        uint256 accumulatedRentalIncomePerShare;
        bool isListed;
    }

    mapping(uint256 => Property) public properties;
    mapping(uint256 => mapping(address => uint256)) public shareholderShares;
    mapping(uint256 => mapping(address => uint256)) public lastClaimedAccumulation;
    mapping(uint256 => address[]) public propertyShareholders;

    IERC20 public paymentToken;

    event PropertyListed(uint256 indexed tokenId, string propertyAddress, uint256 totalShares, uint256 pricePerShare, uint256 monthlyRentalIncome);
    event SharesPurchased(uint256 indexed tokenId, address buyer, uint256 shares);
    event SharesSold(uint256 indexed tokenId, address seller, uint256 shares);
    event RentalIncomeClaimed(uint256 indexed tokenId, address shareholder, uint256 amount);

    constructor(address _paymentToken) ERC721("RealEstateToken", "RET") {
        paymentToken = IERC20(_paymentToken);
    }

    function listProperty(
        string memory propertyAddress,
        string memory _tokenURI,
        uint256 totalShares,
        uint256 pricePerShare,
        uint256 monthlyRentalIncome
    ) external onlyOwner {
        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();

        _safeMint(msg.sender, newTokenId);
        _setTokenURI(newTokenId, _tokenURI);

        properties[newTokenId] = Property(
            newTokenId,
            propertyAddress,
            totalShares,
            totalShares,
            pricePerShare,
            monthlyRentalIncome,
            block.timestamp,
            0,
            true
        );

        emit PropertyListed(newTokenId, propertyAddress, totalShares, pricePerShare, monthlyRentalIncome);
    }

    function buyShares(uint256 tokenId, uint256 shares) external {
        Property storage property = properties[tokenId];
        require(property.isListed, "Property is not listed");
        require(shares <= property.availableShares, "Not enough shares available");

        uint256 totalCost = shares * property.pricePerShare;
        require(paymentToken.transferFrom(msg.sender, address(this), totalCost), "Payment failed");

        _accumulateRentalIncome(tokenId);
        
        property.availableShares -= shares;
        shareholderShares[tokenId][msg.sender] += shares;
        lastClaimedAccumulation[tokenId][msg.sender] = property.accumulatedRentalIncomePerShare;
        propertyShareholders[tokenId].push(msg.sender);

        emit SharesPurchased(tokenId, msg.sender, shares);
    }

    function sellShares(uint256 tokenId, uint256 shares) external {
        Property storage property = properties[tokenId];
        require(shareholderShares[tokenId][msg.sender] >= shares, "Not enough shares to sell");

        _accumulateRentalIncome(tokenId);
        _claimRentalIncome(tokenId);

        uint256 totalPayment = shares * property.pricePerShare;
        require(paymentToken.transfer(msg.sender, totalPayment), "Payment failed");

        property.availableShares += shares;
        shareholderShares[tokenId][msg.sender] -= shares;

        emit SharesSold(tokenId, msg.sender, shares);
    }

    function _accumulateRentalIncome(uint256 tokenId) internal {
        Property storage property = properties[tokenId];
        uint256 timePassed = block.timestamp - property.lastAccumulationTimestamp;
        uint256 monthsPassed = timePassed / 30 days;
        
        if (monthsPassed > 0) {
            uint256 newRentalIncome = property.monthlyRentalIncome * monthsPassed;
            property.accumulatedRentalIncomePerShare += (newRentalIncome * 1e18) / property.totalShares;
            property.lastAccumulationTimestamp += monthsPassed * 30 days;
        }
    }

    function claimRentalIncome(uint256 tokenId) external {
        _accumulateRentalIncome(tokenId);
        _claimRentalIncome(tokenId);
    }

    function _claimRentalIncome(uint256 tokenId) internal {
        Property storage property = properties[tokenId];
        uint256 shares = shareholderShares[tokenId][msg.sender];
        require(shares > 0, "No shares owned");

        uint256 accumulatedPerShare = property.accumulatedRentalIncomePerShare - lastClaimedAccumulation[tokenId][msg.sender];
        uint256 rentalIncome = (accumulatedPerShare * shares) / 1e18;

        if (rentalIncome > 0) {
            lastClaimedAccumulation[tokenId][msg.sender] = property.accumulatedRentalIncomePerShare;
            require(paymentToken.transfer(msg.sender, rentalIncome), "Rental income transfer failed");
            emit RentalIncomeClaimed(tokenId, msg.sender, rentalIncome);
        }
    }

    function getPropertyMetadata(uint256 tokenId) external view returns (Property memory) {
        return properties[tokenId];
    }

    function getShareholderShares(uint256 tokenId, address shareholder) external view returns (uint256) {
        return shareholderShares[tokenId][shareholder];
    }

    function getClaimableRentalIncome(uint256 tokenId, address shareholder) external view returns (uint256) {
        Property storage property = properties[tokenId];
        uint256 shares = shareholderShares[tokenId][shareholder];
        if (shares == 0) return 0;

        uint256 accumulatedPerShare = property.accumulatedRentalIncomePerShare - lastClaimedAccumulation[tokenId][shareholder];
        return (accumulatedPerShare * shares) / 1e18;
    }

    // Override functions
    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, ERC721URIStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
