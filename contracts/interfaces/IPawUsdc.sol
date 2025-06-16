// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IPawUSDC {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
    function decimals() external view returns (uint8);
    function setBorrowingPool(address _pool) external;
}
