// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract RES_TOKEN is ERC20, Ownable {
  constructor(
    string memory _name,
    string memory _symbol
  ) ERC20(_name, _symbol) {}

  function burn(uint256 _amount) public {
    _burn(msg.sender, _amount);
  }

  function mint(address _receiver, uint256 _amount) external onlyOwner {
    _mint(_receiver, _amount);
  }
}
