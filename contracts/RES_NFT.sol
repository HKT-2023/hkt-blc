// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract RES_NFT is ERC721, Ownable {
  uint256 nftId = 1;
  string uri = "";

  constructor(
    string memory _name,
    string memory _symbol
  ) ERC721(_name, _symbol) {}

  function burn(uint256 _tokenId) public {
    _burn(_tokenId);
  }

  function mint(address _receiver) external onlyOwner returns (uint256 _nftId) {
    _nftId = nftId++;
    _mint(_receiver, _nftId);
  }

  function changeURI(string memory _uri) public onlyOwner {
    uri = _uri;
  }

  // internal function
  function _baseURI() internal view override(ERC721) returns (string memory) {
    return uri;
  }
}
