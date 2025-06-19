// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MLP is ERC20, Ownable(msg.sender) {
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply
    ) ERC20(_name, _symbol) {
        _mint(msg.sender, _initialSupply * 10 ** decimals());
    }

    // Optional: Function to mint more tokens (only owner)
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    // Optional: Function to burn tokens (destroy)
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
