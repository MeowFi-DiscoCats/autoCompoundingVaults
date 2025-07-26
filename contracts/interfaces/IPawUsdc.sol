// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IPawUSDC {
    function initialize() external;
    function setBorrowingPool(address _pool) external;
    function mint(address to, uint256 usdcAmount) external;
    function burn(address from, uint256 pawUSDCAmount) external;
    function burnWithFee(address from, uint256 pawUSDCAmount, uint256 feeBps) external;
    function accrueInterest(uint256 interestAmount) external;
    
    // Admin functions
    function approveUSDCForPool() external;
    function transferUSDCToVault(address vault, uint256 amount) external;
    
    // Interest-bearing functions
    function usdcToPawUSDC(uint256 usdcAmount) external view returns (uint256);
    function pawUSDCToUSDC(uint256 pawUSDCAmount) external view returns (uint256);
    function getExchangeRate() external view returns (uint256);
    function getTotalUnderlying() external view returns (uint256);
    function getUnderlyingBalance(address user) external view returns (uint256);
    
    // Standard ERC20 functions
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    
    // State variables
    function borrowingPool() external view returns (address);
    function exchangeRate() external view returns (uint256);
    function totalUnderlying() external view returns (uint256);
    function lastUpdateTime() external view returns (uint256);
    function totalRedemptionFees() external view returns (uint256);
    function getTotalRedemptionFees() external view returns (uint256);
    function repayPrincipal(uint256 amount) external;
} 