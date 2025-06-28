// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PawUSDC is ERC20Upgradeable, OwnableUpgradeable {
    using Math for uint256;
    
    address public borrowingPool;
    address public usdc; // Add USDC token address
    uint256 public protocolUSDCBalance; // Track protocol-controlled USDC
    
    // Interest-bearing mechanism
    uint256 public exchangeRate; // Exchange rate between PawUSDC and USDC (scaled by 1e18)
    uint256 public totalUnderlying; // Total USDC underlying all PawUSDC tokens
    uint256 public lastUpdateTime;
    bool public hasAccruedInterest; // Track if interest has ever been accrued
    uint256 public totalRedemptionFees; // Track total redemption fees collected
    
    uint256 public constant INITIAL_EXCHANGE_RATE = 1e18; // 1:1 initial rate
    uint256 public constant BASIS_POINTS = 10000;
    
    event ExchangeRateUpdated(uint256 oldRate, uint256 newRate, uint256 timestamp);
    event InterestAccrued(uint256 amount, uint256 newExchangeRate, uint256 timestamp);
    event RedemptionFeeCollected(uint256 amount, uint256 newExchangeRate, uint256 timestamp);
    
    function initialize(address _usdc) public initializer {
        __ERC20_init("pawUSDC", "pawUSDC");
        __Ownable_init(msg.sender);
        require(_usdc != address(0), "Invalid USDC address");
        usdc = _usdc;
        exchangeRate = INITIAL_EXCHANGE_RATE;
        lastUpdateTime = block.timestamp;
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
    
    // Convert USDC amount to PawUSDC amount using current exchange rate
    function usdcToPawUSDC(uint256 usdcAmount) public view returns (uint256) {
        if (exchangeRate == 0) return usdcAmount;
        return usdcAmount.mulDiv(1e18, exchangeRate, Math.Rounding.Floor);
    }
    
    // Convert PawUSDC amount to USDC amount using current exchange rate
    function pawUSDCToUSDC(uint256 pawUSDCAmount) public view returns (uint256) {
        return pawUSDCAmount.mulDiv(exchangeRate, 1e18, Math.Rounding.Floor);
    }
    
    // Accrue interest and update exchange rate
    function accrueInterest(uint256 interestAmount) external onlyPool {
        require(interestAmount > 0, "Interest amount must be positive");
        require(totalSupply() > 0, "No tokens minted yet");
        
        uint256 oldExchangeRate = exchangeRate;
        
        // Update total underlying
        totalUnderlying += interestAmount;
        protocolUSDCBalance += interestAmount;
        
        // Calculate new exchange rate
        // New rate = (Total underlying) / (Total PawUSDC supply)
        exchangeRate = totalUnderlying.mulDiv(1e18, totalSupply(), Math.Rounding.Floor);
        
        lastUpdateTime = block.timestamp;
        hasAccruedInterest = true;
        
        emit InterestAccrued(interestAmount, exchangeRate, block.timestamp);
        emit ExchangeRateUpdated(oldExchangeRate, exchangeRate, block.timestamp);
    }
    
    // Mint PawUSDC tokens based on USDC deposit
    function mint(address to, uint256 usdcAmount) external onlyPool {
        require(usdcAmount > 0, "Amount must be positive");
        
        // ✅ FIXED: USDC is already transferred to this contract (like cTokens)
        // No need to transferFrom since USDC is already here
        uint256 pawUSDCAmount = usdcToPawUSDC(usdcAmount);
        require(pawUSDCAmount > 0, "Invalid PawUSDC amount");
        
        _mint(to, pawUSDCAmount);
        totalUnderlying += usdcAmount;
        protocolUSDCBalance += usdcAmount;
        
        // Update exchange rate after minting
        if (totalSupply() > 0) {
            exchangeRate = totalUnderlying.mulDiv(1e18, totalSupply(), Math.Rounding.Floor);
        }
    }

    //
    
    // Burn PawUSDC tokens and return USDC based on current exchange rate
    function burn(address from, uint256 pawUSDCAmount) external onlyPool {
        require(pawUSDCAmount > 0, "Amount must be positive");
        require(balanceOf(from) >= pawUSDCAmount, "Insufficient balance");
        
        uint256 usdcAmount = pawUSDCToUSDC(pawUSDCAmount);
        require(usdcAmount > 0, "Invalid USDC amount");
        
        _burn(from, pawUSDCAmount);
        totalUnderlying -= usdcAmount;
        protocolUSDCBalance -= usdcAmount;
        IERC20(usdc).transfer(from, usdcAmount);
        
        // Update exchange rate after burning
        if (totalSupply() > 0) {
            exchangeRate = totalUnderlying.mulDiv(1e18, totalSupply(), Math.Rounding.Floor);
        }
        // DO NOT reset exchange rate when totalSupply becomes 0
        // This preserves accumulated interest for future depositors
        // Only reset if no interest has ever been accrued (fresh start)
        else if (!hasAccruedInterest) {
            exchangeRate = INITIAL_EXCHANGE_RATE;
        }
        // If interest has been accrued but totalSupply = 0, keep the current exchange rate
        // This ensures accumulated interest is preserved for future depositors
    }

    // Burn PawUSDC tokens with redemption fee
    function burnWithFee(address from, uint256 pawUSDCAmount, uint256 feeBps) external onlyPool {
        require(pawUSDCAmount > 0, "Amount must be positive");
        require(balanceOf(from) >= pawUSDCAmount, "Insufficient balance");
        
        uint256 usdcAmount = pawUSDCToUSDC(pawUSDCAmount);
        require(usdcAmount > 0, "Invalid USDC amount");
        
        // Calculate redemption fee
        uint256 redemptionFee = usdcAmount.mulDiv(feeBps, 10000, Math.Rounding.Floor);
        uint256 netAmountToUser = usdcAmount - redemptionFee;
        
        _burn(from, pawUSDCAmount);
        
        // Only subtract the net amount from totalUnderlying and protocolUSDCBalance
        // The redemption fee remains in the contract for remaining PawUSDC holders
        totalUnderlying -= netAmountToUser;
        protocolUSDCBalance -= netAmountToUser;
        
        // Track redemption fees as accrued value
        totalRedemptionFees += redemptionFee;
        
        // Transfer net amount to user
        IERC20(usdc).transfer(from, netAmountToUser);
        
        // Redemption fee stays in PawUSDC contract
        // This benefits remaining PawUSDC holders by increasing their exchange rate
        
        // Update exchange rate after burning
        if (totalSupply() > 0) {
            exchangeRate = totalUnderlying.mulDiv(1e18, totalSupply(), Math.Rounding.Floor);
        }
        // DO NOT reset exchange rate when totalSupply becomes 0
        // This preserves accumulated interest and redemption fees for future depositors
        // Only reset if no interest or redemption fees have ever been accrued (fresh start)
        else if (!hasAccruedInterest && totalRedemptionFees == 0) {
            exchangeRate = INITIAL_EXCHANGE_RATE;
        }
        // If interest or redemption fees have been accrued but totalSupply = 0, keep the current exchange rate
        // This ensures accumulated value is preserved for future depositors
        
        emit RedemptionFeeCollected(redemptionFee, exchangeRate, block.timestamp);
    }
    
    // Get current exchange rate
    function getExchangeRate() external view returns (uint256) {
        return exchangeRate;
    }
    
    // Get total underlying USDC
    function getTotalUnderlying() external view returns (uint256) {
        return totalUnderlying;
    }
    
    // Get user's underlying USDC balance
    function getUnderlyingBalance(address user) external view returns (uint256) {
        return pawUSDCToUSDC(balanceOf(user));
    }

    // Get total redemption fees collected
    function getTotalRedemptionFees() external view returns (uint256) {
        return totalRedemptionFees;
    }

    // Admin function to sweep excess USDC (not tracked by protocolUSDCBalance)
    function sweepStuckUSDC(address to) external onlyOwner {
        uint256 actualBalance = IERC20(usdc).balanceOf(address(this));
        require(actualBalance > protocolUSDCBalance, "No excess USDC");
        uint256 excess = actualBalance - protocolUSDCBalance;
        IERC20(usdc).transfer(to, excess);
    }
    
    // Transfer USDC to vault (called by borrowing pool)
    function transferUSDCToVault(address vault, uint256 amount) external onlyPool {
        require(amount > 0, "Amount must be positive");
        require(amount <= protocolUSDCBalance, "Insufficient USDC balance");
        
        protocolUSDCBalance -= amount;
        IERC20(usdc).transfer(vault, amount);
    }
}
// usdc=0xf817257fed379853cDe0fa4F97AB987181B1E5Ea
// tokenA=0x3a98250F98Dd388C211206983453837C8365BDc1
// tokenB=0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701
// bubbleVault=0x81f337e24031D6136D7C1EDF38E9648679Eb9f1c
// bubbleRouter=0x0f2D067f8438869da670eFc855eACAC71616ca31
// lpToken=0x3e9A26b6edEcE5999aedEec9B093C851CdfeC529
// pricefetcher=0x85931b62e078AeBB4DeADf841be5592491C2efb7
// octo=0xb6091233aAcACbA45225a2B2121BBaC807aF4255

//   maxLTV: 7000
//    liquidationThreshold: 7500
//    liquidationPenalty: 500
//    baseRate: 1000
//    multiplier: 2000
//    jumpMultiplier: 5000
//    kink: 8000
//    protocolFeeRate: 2000
//    vaultFeeRate: 1000
//    lenderShare: 7000
//    slippageBPS: 100
//    lpToken: "YOUR_LP_TOKEN_ADDRESS"
//    octoRouter: "YOUR_OCTO_ROUTER_ADDRESS"
//    bubbleRouter: "YOUR_BUBBLE_ROUTER_ADDRESS"
//    liquidationVaultShare: 4000
//    liquidationProtocolShare: 2000
//    liquidationLenderShare: 4000