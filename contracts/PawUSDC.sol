// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract PawUSDC is ERC20Upgradeable, OwnableUpgradeable {
    address public borrowingPool;
    
    function initialize() public initializer {
        __ERC20_init("pawUSDC", "pawUSDC");
        __Ownable_init(msg.sender);
    }


    function decimals() public pure override returns (uint8) {
        return 6;
    }
    
    function setBorrowingPool(address _pool) external onlyOwner {
        borrowingPool = _pool;
    }
    
    modifier onlyPool() {
        require(msg.sender == borrowingPool, "Only pool");
        _;
    }
    
    function mint(address to, uint256 amount) external onlyPool {
        _mint(to, amount);
    }
    
    function burn(address from, uint256 amount) external onlyPool {
        _burn(from, amount);
    }
}
