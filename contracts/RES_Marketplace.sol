// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract RES_Marketplace is Ownable, ReentrancyGuard {
  struct ListNFT {
    address nft;
    uint256 tokenId;
    address seller;
    address payToken;
    uint256 price;
    bool sold;
  }

  struct OfferNFT {
    address nft;
    uint256 tokenId;
    address offerer;
    address payToken;
    uint256 offerPrice;
    bool accepted;
  }

  struct AuctionNFT {
    address nft;
    uint256 tokenId;
    address creator;
    address payToken;
    uint256 initialPrice;
    uint256 ceilingPrice;
    uint256 minBid;
    uint256 startTime;
    uint256 endTime;
    address lastBidder;
    uint256 heighestBid;
    address winner;
    bool success;
  }

  mapping(address => bool) private payableToken;
  address[] private tokens;
  uint256 public royalFee = 500;
  uint256 constant divisor = 10000;

  // nft => tokenId => list struct
  mapping(address => mapping(uint256 => ListNFT)) private listNfts;

  // nft => tokenId => offerer address => offer struct
  mapping(address => mapping(uint256 => mapping(address => OfferNFT)))
    private offerNfts;

  // auciton index => bidding counts => bidder address => bid price
  mapping(uint256 => mapping(uint256 => mapping(address => uint256)))
    private bidPrices;

  mapping(address => mapping(uint256 => address[])) public offerList;

  // nft => tokenId => acuton struct
  mapping(address => mapping(uint256 => AuctionNFT)) private auctionNfts;

  // events
  event ListedNFT(
    address indexed nft,
    uint256 indexed tokenId,
    address payToken,
    uint256 price,
    address indexed seller
  );
  event BoughtNFT(
    address indexed nft,
    uint256 indexed tokenId,
    address payToken,
    uint256 price,
    address seller,
    address indexed buyer
  );
  event OfferredNFT(
    address indexed nft,
    uint256 indexed tokenId,
    address payToken,
    uint256 offerPrice,
    address indexed offerer
  );
  event CanceledOfferredNFT(
    address indexed nft,
    uint256 indexed tokenId,
    address payToken,
    uint256 offerPrice,
    address indexed offerer
  );
  event AcceptedNFT(
    address indexed nft,
    uint256 indexed tokenId,
    address payToken,
    uint256 offerPrice,
    address offerer,
    address indexed nftOwner
  );
  event CreatedAuction(
    address indexed nft,
    uint256 indexed tokenId,
    address payToken,
    uint256 price,
    uint256 minBid,
    uint256 startTime,
    uint256 endTime,
    address indexed creator
  );

  event PlacedBid(
    address indexed nft,
    uint256 indexed tokenId,
    address payToken,
    uint256 bidPrice,
    address indexed bidder
  );

  event ResultedAuction(
    address indexed nft,
    uint256 indexed tokenId,
    address creator,
    address indexed winner,
    uint256 price,
    address caller
  );

  modifier isListedNFT(address _nft, uint256 _tokenId) {
    ListNFT memory listedNFT = listNfts[_nft][_tokenId];
    require(listedNFT.seller != address(0) && !listedNFT.sold, "not listed");
    _;
  }

  modifier isNotListedNFT(address _nft, uint256 _tokenId) {
    ListNFT memory listedNFT = listNfts[_nft][_tokenId];
    require(listedNFT.seller == address(0) || listedNFT.sold, "already listed");
    _;
  }

  modifier isOfferredNFT(
    address _nft,
    uint256 _tokenId,
    address _offerer
  ) {
    OfferNFT memory offer = offerNfts[_nft][_tokenId][_offerer];
    require(
      offer.offerPrice > 0 && offer.offerer != address(0),
      "not offerred nft"
    );
    _;
  }

  modifier isAuction(address _nft, uint256 _tokenId) {
    AuctionNFT memory auction = auctionNfts[_nft][_tokenId];
    require(
      auction.nft != address(0) && !auction.success,
      "auction not created yet"
    );
    _;
  }

  modifier isNotAuction(address _nft, uint256 _tokenId) {
    AuctionNFT memory auction = auctionNfts[_nft][_tokenId];
    require(
      auction.nft == address(0) || auction.success,
      "auction already created"
    );
    _;
  }

  function setRoyalFee(uint256 _royalFee) public onlyOwner {
    require(_royalFee < divisor, "invalid royal fee");
    royalFee = _royalFee;
  }

  function putNftOnMarketplace(
    address _nft,
    uint256 _tokenId,
    address _payToken,
    uint256 _price
  ) external payable {
    transferNFTInternal(_nft, msg.sender, address(this), _tokenId);
    listNfts[_nft][_tokenId] = ListNFT({
      nft: _nft,
      tokenId: _tokenId,
      seller: msg.sender,
      payToken: _payToken,
      price: _price,
      sold: false
    });
    emit ListedNFT(_nft, _tokenId, _payToken, _price, msg.sender);
  }

  function putNftOffMarketplace(
    address _nft,
    uint256 _tokenId
  ) external payable isListedNFT(_nft, _tokenId) {
    ListNFT memory listedNFT = listNfts[_nft][_tokenId];
    require(listedNFT.seller == msg.sender, "not listed owner");
    transferNFTInternal(_nft, address(this), msg.sender, _tokenId);
    delete listNfts[_nft][_tokenId];
    address winner = address(0); // no winner as put off NFT
    returnFee(_nft, _tokenId, winner);
  }

  function buy(
    address _nft,
    uint256 _tokenId,
    address _payToken,
    uint256 _price
  ) external payable isListedNFT(_nft, _tokenId) nonReentrant {
    ListNFT storage listedNft = listNfts[_nft][_tokenId];
    require(
      _payToken != address(0) && _payToken == listedNft.payToken,
      "invalid pay token"
    );
    require(!listedNft.sold, "nft already sold");
    require(_price >= listedNft.price, "invalid price");
    listedNft.sold = true;
    uint256 totalPrice = _price;

    // Transfer to nft owner
    uint256 buyFee = getRoyalFeeAmount(totalPrice);
    transferTokenInternal(listedNft.payToken, msg.sender, owner(), buyFee);
    transferTokenInternal(
      listedNft.payToken,
      msg.sender,
      listedNft.seller,
      totalPrice - buyFee
    );

    // Transfer NFT to buyer
    transferNFTInternal(
      listedNft.nft,
      address(this),
      msg.sender,
      listedNft.tokenId
    );

    emit BoughtNFT(
      listedNft.nft,
      listedNft.tokenId,
      listedNft.payToken,
      _price,
      listedNft.seller,
      msg.sender
    );

    returnFee(_nft, _tokenId, address(0));
  }

  function makeOffer(
    address _nft,
    uint256 _tokenId,
    address _payToken,
    uint256 _offerPrice
  ) external payable isListedNFT(_nft, _tokenId) nonReentrant {
    require(_offerPrice > 0, "price can not 0");
    ListNFT memory nft = listNfts[_nft][_tokenId];
    OfferNFT storage _offerNft = offerNfts[_nft][_tokenId][msg.sender];

    if (_offerNft.offerer == address(0)) {
      transferTokenInternal(
        nft.payToken,
        msg.sender,
        address(this),
        _offerPrice
      );
      _offerNft.nft = nft.nft;
      _offerNft.tokenId = nft.tokenId;
      _offerNft.offerer = msg.sender;
      _offerNft.payToken = _payToken;
      _offerNft.offerPrice = _offerPrice;
      _offerNft.accepted = false;
      offerList[_nft][_tokenId].push(msg.sender);
    } else {
      require(_payToken == _offerNft.payToken, "Invalid tokenID");
      uint256 initialOfferPrice = _offerNft.offerPrice;
      if (_offerPrice >= initialOfferPrice) {
        uint256 extraFee = _offerPrice - initialOfferPrice;
        transferTokenInternal(
          nft.payToken,
          msg.sender,
          address(this),
          extraFee
        );
        _offerNft.offerPrice = _offerPrice;
      } else {
        uint256 repayFee = initialOfferPrice - _offerPrice;
        transferTokenInternal(
          nft.payToken,
          address(this),
          msg.sender,
          repayFee
        );
        _offerNft.offerPrice = _offerPrice;
      }
    }

    emit OfferredNFT(
      nft.nft,
      nft.tokenId,
      nft.payToken,
      _offerPrice,
      msg.sender
    );
  }

  function cancelOffer(
    address _nft,
    uint256 _tokenId
  ) external payable isOfferredNFT(_nft, _tokenId, msg.sender) nonReentrant {
    OfferNFT memory offer = offerNfts[_nft][_tokenId][msg.sender];
    require(offer.offerer == msg.sender, "not offerer");
    require(!offer.accepted, "offer already accepted");
    delete offerNfts[_nft][_tokenId][msg.sender];
    removeOfferer(offerList[_nft][_tokenId], msg.sender);
    transferTokenInternal(
      offer.payToken,
      address(this),
      msg.sender,
      offer.offerPrice
    );
    emit CanceledOfferredNFT(
      offer.nft,
      offer.tokenId,
      offer.payToken,
      offer.offerPrice,
      msg.sender
    );
  }

  function acceptOfferNFT(
    address _nft,
    uint256 _tokenId,
    address _offerer
  )
    external
    payable
    isOfferredNFT(_nft, _tokenId, _offerer)
    isListedNFT(_nft, _tokenId)
    nonReentrant
  {
    require(listNfts[_nft][_tokenId].seller == msg.sender, "not listed owner");
    OfferNFT storage offer = offerNfts[_nft][_tokenId][_offerer];
    ListNFT storage list = listNfts[offer.nft][offer.tokenId];
    require(!list.sold, "already sold");
    require(!offer.accepted, "offer already accepted");

    list.sold = true;
    offer.accepted = true;

    uint256 offerPrice = offer.offerPrice;
    uint256 totalPrice = offerPrice;

    // Transfer to seller
    uint256 buyFee = getRoyalFeeAmount(totalPrice);

    transferTokenInternal(offer.payToken, address(this), owner(), buyFee);
    transferTokenInternal(
      offer.payToken,
      address(this),
      list.seller,
      totalPrice - buyFee
    );

    // Transfer NFT to offerer
    transferNFTInternal(list.nft, address(this), offer.offerer, list.tokenId);

    emit AcceptedNFT(
      offer.nft,
      offer.tokenId,
      offer.payToken,
      offer.offerPrice,
      offer.offerer,
      list.seller
    );

    returnFee(_nft, _tokenId, _offerer);
  }

  function createAuction(
    address _nft,
    uint256 _tokenId,
    address _payToken,
    uint256 _price,
    uint256 _ceilingPrice,
    uint256 _minBid,
    uint256 _startTime,
    uint256 _endTime
  ) external payable isNotAuction(_nft, _tokenId) {
    require(_endTime > _startTime, "invalid end time");
    require(_ceilingPrice >= _price, "invalid ceiling price");
    require(_price >= _minBid, "invalid price");

    transferNFTInternal(_nft, msg.sender, address(this), _tokenId);

    auctionNfts[_nft][_tokenId] = AuctionNFT({
      nft: _nft,
      tokenId: _tokenId,
      creator: msg.sender,
      payToken: _payToken,
      initialPrice: _price,
      ceilingPrice: _ceilingPrice,
      minBid: _minBid,
      startTime: _startTime,
      endTime: _endTime,
      lastBidder: address(0),
      heighestBid: _price - _minBid,
      winner: address(0),
      success: false
    });

    emit CreatedAuction(
      _nft,
      _tokenId,
      _payToken,
      _price,
      _minBid,
      _startTime,
      _endTime,
      msg.sender
    );
  }

  function cancelAuction(
    address _nft,
    uint256 _tokenId
  ) external payable isAuction(_nft, _tokenId) {
    AuctionNFT memory auction = auctionNfts[_nft][_tokenId];
    require(auction.creator == msg.sender, "not auction creator");
    require(auction.lastBidder == address(0), "already have bidder");
    transferNFTInternal(_nft, address(this), msg.sender, _tokenId);
    delete auctionNfts[_nft][_tokenId];
  }

  function placeBid(
    address _nft,
    uint256 _tokenId,
    uint256 _bidPrice
  ) external payable isAuction(_nft, _tokenId) nonReentrant {
    require(
      block.timestamp >= auctionNfts[_nft][_tokenId].startTime,
      "auction not start"
    );
    require(
      block.timestamp <= auctionNfts[_nft][_tokenId].endTime,
      "auction ended"
    );
    require(
      _bidPrice >=
        auctionNfts[_nft][_tokenId].heighestBid +
          auctionNfts[_nft][_tokenId].minBid,
      "less than min bid price"
    );

    AuctionNFT storage auction = auctionNfts[_nft][_tokenId];
    transferTokenInternal(
      auction.payToken,
      msg.sender,
      address(this),
      _bidPrice
    );

    if (auction.lastBidder != address(0)) {
      address lastBidder = auction.lastBidder;
      uint256 lastBidPrice = auction.heighestBid;

      // Transfer back to last bidder
      transferTokenInternal(
        auction.payToken,
        address(this),
        lastBidder,
        lastBidPrice
      );
    }

    // Set new heighest bid price
    auction.lastBidder = msg.sender;
    auction.heighestBid = _bidPrice;

    emit PlacedBid(_nft, _tokenId, auction.payToken, _bidPrice, msg.sender);

    if (_bidPrice >= auction.ceilingPrice) {
      _processEndAuction(_nft, _tokenId);
    }
  }

  function completeBid(
    address _nft,
    uint256 _tokenId
  ) external payable nonReentrant {
    require(!auctionNfts[_nft][_tokenId].success, "already resulted");
    require(
      msg.sender == owner() ||
        msg.sender == auctionNfts[_nft][_tokenId].creator ||
        msg.sender == auctionNfts[_nft][_tokenId].lastBidder,
      "not creator, winner, or owner"
    );
    require(
      block.timestamp > auctionNfts[_nft][_tokenId].endTime ||
        msg.sender == auctionNfts[_nft][_tokenId].creator,
      "auction not ended or require owner for soon complete"
    );

    _processEndAuction(_nft, _tokenId);
  }

  // for test only
  function getTime() public view returns (uint256) {
    return block.timestamp;
  }

  function _processEndAuction(address _nft, uint256 _tokenId) internal {
    AuctionNFT storage auction = auctionNfts[_nft][_tokenId];
    auction.success = true;
    auction.winner = auction.creator;

    uint256 heighestBid = auction.heighestBid;
    uint256 totalPrice = heighestBid;
    uint256 royalFeeAmount = getRoyalFeeAmount(totalPrice);

    // Transfer to auction creator, the royalFee to admin wallet
    transferTokenInternal(
      auction.payToken,
      address(this),
      auction.creator,
      totalPrice - royalFeeAmount
    );

    transferTokenInternal(
      auction.payToken,
      address(this),
      owner(),
      royalFeeAmount
    );
    // Transfer NFT to the winnertoken
    transferNFTInternal(
      auction.nft,
      address(this),
      auction.lastBidder,
      auction.tokenId
    );
    emit ResultedAuction(
      _nft,
      _tokenId,
      auction.creator,
      auction.lastBidder,
      auction.heighestBid,
      msg.sender
    );
  }

  function getListedNFT(
    address _nft,
    uint256 _tokenId
  ) public view returns (ListNFT memory) {
    return listNfts[_nft][_tokenId];
  }

  function transferTokenInternal(
    address _token,
    address _sender,
    address _receiver,
    uint256 _amount
  ) internal {
    IERC20 resReal = IERC20(_token);
    resReal.transferFrom(_sender, _receiver, _amount);
  }

  function transferNFTInternal(
    address _token,
    address _sender,
    address _receiver,
    uint256 _tokenId
  ) internal {
    IERC721 resNft = IERC721(_token);
    resNft.transferFrom(_sender, _receiver, _tokenId);
  }

  function getRoyalFeeAmount(
    uint256 _tokenAmount
  ) public view returns (uint256) {
    return (_tokenAmount * royalFee) / divisor;
  }

  function removeOfferer(address[] storage array, address canceller) internal {
    for (uint256 i = 0; i < array.length; i++) {
      if (array[i] == canceller) {
        array[i] = address(0);
        break;
      }
    }
  }

  function returnFee(address _nft, uint256 _tokenId, address _winner) internal {
    address[] memory _offerList = offerList[_nft][_tokenId];
    for (uint256 i = 0; i < _offerList.length; i++) {
      // _winner will be the zero address if cancel all offers
      if (
        _offerList[i] != address(0) &&
        (_winner == address(0) || _offerList[i] != _winner)
      ) {
        OfferNFT memory offer = offerNfts[_nft][_tokenId][_offerList[i]];
        transferTokenInternal(
          offer.payToken,
          address(this),
          _offerList[i],
          offer.offerPrice
        );
        delete offerNfts[_nft][_tokenId][_offerList[i]];
      }
    }
    delete offerList[_nft][_tokenId];
  }
}
