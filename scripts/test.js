const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Testing contracts with the account:", deployer.address);

  // Replace these with your actual deployed contract addresses
  // const DEPLOYED_ADDRESSES = {
  //   PawUSDC: "0x62B5F48C753c8b3714915F55660c087dFE4F78Dc", // Replace with actual address
  //   CentralizedLendingPool: "0x2FC4441bbdD7CC54579eAd05674a6103D691c4DC", // Replace with actual address
  //   USDCVault: "0xdc4Ae031e2E515947f8bB2C47Da5a0915CaBdDcc", // Replace with actual address (proxy address)
  //   USDCVaultFactory: "0xbE4A62d9618f8Dbf71a2C792f12F9186f8464F80", // Replace with actual address
  // };

  const DEPLOYED_ADDRESSES = {
    PawUSDC: "0x7426bd27cC5826C0A126cD6793f79F011746A86b", // Replace with actual address
    CentralizedLendingPool: "0xa3aC5bbD292a01537010c84DE4055B38a2A43E5C", // Replace with actual address
    USDCVault: "0x822b50B9dA2D347569E0a2946dB5eC6bF8C38303", // Replace with actual address (proxy address)
    USDCVaultFactory: "0xcd09894FbF2DED71a0e0a0dc2DE749637C597F0C", // Replace with actual address
  };

  // Contract addresses from PawUSDC.sol comments
  const USDC_ADDRESS = "0xf817257fed379853cDe0fa4F97AB987181B1E5Ea";
  const TOKEN_A_ADDRESS = "0x3a98250F98Dd388C211206983453837C8365BDc1"; // SHMON
  const TOKEN_B_ADDRESS = "0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701"; // WMON
  const BUBBLE_VAULT_ADDRESS = "0x81f337e24031D6136D7C1EDF38E9648679Eb9f1c";
  const BUBBLE_ROUTER_ADDRESS = "0x0f2D067f8438869da670eFc855eACAC71616ca31";
  const LP_TOKEN_ADDRESS = "0x3e9A26b6edEcE5999aedEec9B093C851CdfeC529";
  const PRICE_FETCHER_ADDRESS = "0x85931b62e078AeBB4DeADf841be5592491C2efb7";
  const OCTO_ROUTER_ADDRESS = "0xb6091233aAcACbA45225a2B2121BBaC807aF4255";

  try {
    // Get contract instances
    const pawUSDC = await ethers.getContractAt("PawUSDC", DEPLOYED_ADDRESSES.PawUSDC);
    const lendingPool = await ethers.getContractAt("CentralizedLendingPool", DEPLOYED_ADDRESSES.CentralizedLendingPool);
    const usdcVault = await ethers.getContractAt("USDCVault", DEPLOYED_ADDRESSES.USDCVault);
    const usdc = await ethers.getContractAt("IERC20", USDC_ADDRESS);
    const bubbleVault = await ethers.getContractAt("IERC20", BUBBLE_VAULT_ADDRESS);

    console.log("\n=== INITIAL STATE ===");
    await printBalances(usdc, pawUSDC, lendingPool, deployer.address, "Deployer");
    await printSystemState(pawUSDC, lendingPool);

    // ============================================================================
    // TEST 1: USDC LENDING (DEPOSIT)
    // ============================================================================
    
    // console.log("\n=== TEST 1: USDC LENDING (DEPOSIT) ===");
    
    // const lendAmount = ethers.parseUnits("1", 6); // 1 USDC for testing
    
    // // Check if deployer has enough USDC
    // const deployerUSDCBalance = await usdc.balanceOf(deployer.address);
    // console.log("Deployer USDC balance before lending:", ethers.formatUnits(deployerUSDCBalance, 6));
    
    // if (deployerUSDCBalance < lendAmount) {
    //   console.log("❌ Deployer doesn't have enough USDC for lending test");
    //   console.log("Need:", ethers.formatUnits(lendAmount, 6), "USDC");
    //   console.log("Have:", ethers.formatUnits(deployerUSDCBalance, 6), "USDC");
    //   console.log("ℹ️  You may need to get some USDC from a faucet or transfer from another account");
    // } else {
    //   try {
    //     // Approve USDC spending for the lending pool
    //     console.log("Approving USDC spending for lending pool...");
    //     const approveTx = await usdc.connect(deployer).approve(DEPLOYED_ADDRESSES.CentralizedLendingPool, lendAmount);
    //     await approveTx.wait();
    //     console.log("✅ USDC approved for lending pool");
        
    //     // Lend USDC through the vault (which delegates to lending pool)
    //     console.log("Lending USDC through vault...");
    //     const lendTx = await usdcVault.connect(deployer).lendUSDC(lendAmount);
    //     await lendTx.wait();
    //     console.log("✅ USDC lent successfully through vault");
        
    //     // Check balances after lending
    //     console.log("\n=== AFTER LENDING ===");
    //     await printBalances(usdc, pawUSDC, lendingPool, deployer.address, "Deployer");
    //     await printSystemState(pawUSDC, lendingPool);
        
    //     // Check PawUSDC exchange rate
    //     const exchangeRate = await pawUSDC.getExchangeRate();
    //     console.log("PawUSDC Exchange Rate:", ethers.formatUnits(exchangeRate, 18));
        
    //     // Check user's PawUSDC info
    //     const [pawUSDCBalance, underlyingUSDC, currentExchangeRate] = await usdcVault.getPawUSDCHolderInfo(deployer.address);
    //     console.log("PawUSDC Holder Info:");
    //     console.log("  PawUSDC Balance:", ethers.formatUnits(pawUSDCBalance, 6));
    //     console.log("  Underlying USDC:", ethers.formatUnits(underlyingUSDC, 6));
    //     console.log("  Current Exchange Rate:", ethers.formatUnits(currentExchangeRate, 18));
        
    //   } catch (error) {
    //     console.log("❌ Lending failed:", error.message);
    //   }
    // }

    // ============================================================================
    // TEST 2: USDC WITHDRAWAL
    // ============================================================================
    
    // console.log("\n=== TEST 2: USDC WITHDRAWAL ===");
    
    // const deployerPawUSDCBalance = await pawUSDC.balanceOf(deployer.address);
    // console.log("Deployer PawUSDC balance before withdrawal:", ethers.formatUnits(deployerPawUSDCBalance, 6));
    
    // if (deployerPawUSDCBalance > 0) {
    //   try {
    //     // Withdraw half of PawUSDC (to test partial withdrawal)
    //     const withdrawAmount = deployerPawUSDCBalance / 2n;
    //     console.log("Withdrawing half of PawUSDC:", ethers.formatUnits(withdrawAmount, 6));
        
    //     const withdrawTx = await usdcVault.connect(deployer).withdrawUSDC(0);
    //     await withdrawTx.wait();
    //     console.log("✅ USDC withdrawn successfully");
        
    //     // Check balances after withdrawal
    //     console.log("\n=== AFTER WITHDRAWAL ===");
    //     await printBalances(usdc, pawUSDC, lendingPool, deployer.address, "Deployer");
    //     await printSystemState(pawUSDC, lendingPool);
        
    //     // Check redemption fee
    //     const redemptionFeeBPS = await lendingPool.REDEMPTION_FEE_BPS();
    //     console.log("Redemption Fee BPS:", Number(redemptionFeeBPS));
        
    //   } catch (error) {
    //     console.log("❌ Withdrawal failed:", error.message);
    //   }
    // } else {
    //   console.log("❌ Deployer has no PawUSDC to withdraw");
    //   console.log("ℹ️  You need to lend USDC first to get PawUSDC tokens");
    // }

    // ============================================================================
    // TEST 3: BORROWING WITH LP TOKENS
    // ============================================================================
    
    // console.log("\n=== TEST 3: BORROWING WITH LP TOKENS ===");
    
    // // Check deployer's LP token balance
    // const deployerLPBalance = await bubbleVault.balanceOf(deployer.address);
    // console.log("Deployer LP Token balance:", ethers.formatUnits(deployerLPBalance, 18));
    
    // if (deployerLPBalance > 0) {
    //   try {
    //     // Use a small amount for testing (1% of balance)
    //     const collateralAmount = deployerLPBalance / 100n; // 1% of Bubble Vault shares
    //     console.log("Using collateral amount:", ethers.formatUnits(collateralAmount, 18), "Bubble Vault shares");
        
    //     // Get vault configuration
    //     const vaultConfig = await usdcVault.config();
    //     console.log("\nVault Configuration:");
    //     console.log("  Vault active:", vaultConfig.active);
    //     console.log("  Vault borrowing enabled:", vaultConfig.borrowingEnabled);
    //     console.log("  Vault max LTV:", Number(vaultConfig.maxLTV) / 100, "%");
    //     console.log("  Vault slippage BPS:", Number(vaultConfig.slippageBPS));
        
    //     // Get collateral value in USDC and max borrow amount
    //     const [maxBorrowAmount, collateralValueUSDC, minCollateralValueUSDC] = await usdcVault.getMaxBorrowAmountWithSlippage(collateralAmount);
    //     console.log("\nCollateral Analysis:");
    //     console.log("  Collateral value in USDC:", ethers.formatUnits(collateralValueUSDC, 6));
    //     console.log("  Min collateral value (with slippage):", ethers.formatUnits(minCollateralValueUSDC, 6));
    //     console.log("  Max borrow amount:", ethers.formatUnits(maxBorrowAmount, 6), "USDC");
        
    //     // Use a small borrow amount (50% of max to be safe)
    //     const borrowAmount = maxBorrowAmount / 2n;
    //     console.log("Borrowing amount:", ethers.formatUnits(borrowAmount, 6), "USDC");
        
    //     // Check if lending pool has sufficient liquidity
    //     const availableLiquidity = await lendingPool.getAvailableLiquidity();
    //     console.log("Available liquidity in lending pool:", ethers.formatUnits(availableLiquidity, 6), "USDC");
        
    //     if (availableLiquidity >= borrowAmount) {
    //       // Approve LP tokens for vault
    //       console.log("Approving LP tokens for vault...");
    //       const approveTx = await bubbleVault.connect(deployer).approve(DEPLOYED_ADDRESSES.USDCVault, collateralAmount);
    //       await approveTx.wait();
    //       console.log("✅ LP tokens approved for vault");
          
    //       // Borrow USDC
    //       console.log("Borrowing USDC with LP collateral...");
    //       const borrowTx = await usdcVault.connect(deployer).borrow(collateralAmount, borrowAmount);
    //       await borrowTx.wait();
    //       console.log("✅ USDC borrowed successfully");
          
    //       // Check balances after borrowing
    //       console.log("\n=== AFTER BORROWING ===");
    //       await printBalances(usdc, pawUSDC, lendingPool, deployer.address, "Deployer");
    //       await printSystemState(pawUSDC, lendingPool);
          
    //       // Get borrower position
    //       const borrowerPosition = await usdcVault.borrowers(deployer.address);
    //       console.log("\nBorrower Position:");
    //       console.log("  Collateral Amount:", ethers.formatUnits(borrowerPosition.collateralAmount, 18), "LP tokens");
    //       console.log("  Borrowed Amount:", ethers.formatUnits(borrowerPosition.borrowedAmount, 6), "USDC");
    //       console.log("  Accrued Interest:", ethers.formatUnits(borrowerPosition.accruedInterest, 6), "USDC");
    //       console.log("  Is Active:", borrowerPosition.isActive);
          
    //       // Get current debt
    //       const currentDebt = await usdcVault.getCurrentDebt(deployer.address);
    //       console.log("  Current Total Debt:", ethers.formatUnits(currentDebt, 6), "USDC");
          
    //       // Get borrow capacity info
    //       const [collateralValue, maxBorrow, currentDebtInfo, availableCapacity, isHealthy] = await usdcVault.getBorrowCapacityInfo(deployer.address);
    //       console.log("\nBorrow Capacity Info:");
    //       console.log("  Collateral Value:", ethers.formatUnits(collateralValue, 6), "USDC");
    //       console.log("  Max Borrow Amount:", ethers.formatUnits(maxBorrow, 6), "USDC");
    //       console.log("  Current Debt:", ethers.formatUnits(currentDebtInfo, 6), "USDC");
    //       console.log("  Available Borrow Capacity:", ethers.formatUnits(availableCapacity, 6), "USDC");
    //       console.log("  Is Healthy:", isHealthy);
          
    //     } else {
    //       console.log("❌ Insufficient liquidity in lending pool");
    //       console.log("Need:", ethers.formatUnits(borrowAmount, 6), "USDC");
    //       console.log("Available:", ethers.formatUnits(availableLiquidity, 6), "USDC");
    //     }
    //   } catch (error) {
    //     console.log("❌ Borrowing failed:", error.message);
    //   }
    // } else {
    //   console.log("❌ Deployer has no LP tokens for collateral");
    //   console.log("ℹ️  You need to get some LP tokens to use as collateral");
    // }

    // ============================================================================
    // TEST 4: REPAYMENT
    // ============================================================================
    
    // console.log("\n=== TEST 4: REPAYMENT ===");
    
    // // Check if deployer has an active borrowing position
    // const borrowerPosition = await usdcVault.borrowers(deployer.address);
    
    // if (borrowerPosition.isActive && borrowerPosition.borrowedAmount > 0) {
    //   try {
    //     // Get current debt
    //     const currentDebt = await usdcVault.getCurrentDebt(deployer.address);
    //     console.log("Current total debt:", ethers.formatUnits(currentDebt, 6), "USDC");
        
    //     // Check deployer's USDC balance
    //     const deployerUSDCBalance = await usdc.balanceOf(deployer.address);
    //     console.log("Deployer USDC balance:", ethers.formatUnits(deployerUSDCBalance, 6));
        
    //     // DEBUG: Check borrower position details
    //     console.log("\n=== DEBUG: Borrower Position Details ===");
    //     console.log("Borrowed Amount:", ethers.formatUnits(borrowerPosition.borrowedAmount, 6), "USDC");
    //     console.log("Accrued Interest:", ethers.formatUnits(borrowerPosition.accruedInterest, 6), "USDC");
    //     console.log("Is Active:", borrowerPosition.isActive);
    //     console.log("Last Update Time:", borrowerPosition.lastUpdateTime.toString());
        
    //     // DEBUG: Check vault configuration
    //     const vaultConfig = await usdcVault.config();
    //     console.log("\n=== DEBUG: Vault Configuration ===");
    //     console.log("Vault Active:", vaultConfig.active);
    //     console.log("Borrowing Enabled:", vaultConfig.borrowingEnabled);
    //     console.log("Emergency Mode:", await usdcVault.emergencyMode());
    //     console.log("Liquidations Paused:", await usdcVault.liquidationsPaused());
        
    //     // DEBUG: Check lending pool status
    //     console.log("\n=== DEBUG: Lending Pool Status ===");
    //     const lendingPoolAddress = await usdcVault.lendingPool();
    //     console.log("Lending Pool Address:", lendingPoolAddress);
    //     const isVaultRegistered = await lendingPool.vaults(DEPLOYED_ADDRESSES.USDCVault);
    //     console.log("Is Vault Registered:", isVaultRegistered.isActive);
        
    //     // Repay half of the debt
    //     const repayAmount = currentDebt / 2n;
    //     console.log("Repaying amount:", ethers.formatUnits(repayAmount, 6), "USDC");
        
    //     if (deployerUSDCBalance >= repayAmount) {
    //       // Approve USDC spending for vault
    //       console.log("Approving USDC spending for vault...");
    //       const approveTx = await usdc.connect(deployer).approve(DEPLOYED_ADDRESSES.USDCVault, repayAmount);
    //       await approveTx.wait();
    //       console.log("✅ USDC approved for vault");
          
    //       // Check allowance
    //       const allowance = await usdc.allowance(deployer.address, DEPLOYED_ADDRESSES.USDCVault);
    //       console.log("USDC Allowance:", ethers.formatUnits(allowance, 6));
          
    //       // Repay debt
    //       console.log("Repaying debt...");
    //       const repayTx = await usdcVault.connect(deployer).repay(repayAmount);
    //       await repayTx.wait();
    //       console.log("✅ Debt repaid successfully");
          
    //       // Check balances after repayment
    //       console.log("\n=== AFTER REPAYMENT ===");
    //       await printBalances(usdc, pawUSDC, lendingPool, deployer.address, "Deployer");
    //       await printSystemState(pawUSDC, lendingPool);
          
    //       // Get updated borrower position
    //       const updatedPosition = await usdcVault.borrowers(deployer.address);
    //       console.log("\nUpdated Borrower Position:");
    //       console.log("  Collateral Amount:", ethers.formatUnits(updatedPosition.collateralAmount, 18), "LP tokens");
    //       console.log("  Borrowed Amount:", ethers.formatUnits(updatedPosition.borrowedAmount, 6), "USDC");
    //       console.log("  Accrued Interest:", ethers.formatUnits(updatedPosition.accruedInterest, 6), "USDC");
    //       console.log("  Is Active:", updatedPosition.isActive);
          
    //       // Get updated current debt
    //       const updatedDebt = await usdcVault.getCurrentDebt(deployer.address);
    //       console.log("  Updated Current Debt:", ethers.formatUnits(updatedDebt, 6), "USDC");
          
    //     } else {
    //       console.log("❌ Insufficient USDC balance for repayment");
    //       console.log("Need:", ethers.formatUnits(repayAmount, 6), "USDC");
    //       console.log("Have:", ethers.formatUnits(deployerUSDCBalance, 6), "USDC");
    //     }
    //   } catch (error) {
    //     console.log("❌ Repayment failed:", error.message);
    //     console.log("Error details:", error);
        
    //     // Try to get more specific error information
    //     if (error.data) {
    //       console.log("Error data:", error.data);
    //     }
    //     if (error.reason) {
    //       console.log("Error reason:", error.reason);
    //     }
    //   }
    // } else {
    //   console.log("❌ Deployer has no active borrowing position to repay");
    //   console.log("ℹ️  You need to borrow USDC first to test repayment");
    // }

    // ============================================================================
    // TEST 5: FULL REPAYMENT AND COLLATERAL RETURN
    // ============================================================================
    
    console.log("\n=== TEST 5: FULL REPAYMENT AND COLLATERAL RETURN ===");
    
    // Check if deployer has an active borrowing position
    const finalPosition = await usdcVault.borrowers(deployer.address);
    
    if (finalPosition.isActive && finalPosition.borrowedAmount > 0) {
      try {
        // Get current debt
        const currentDebt = await usdcVault.getCurrentDebt(deployer.address);
        console.log("Current total debt:", ethers.formatUnits(currentDebt, 6), "USDC");
        
        // Check deployer's USDC balance
        const deployerUSDCBalance = await usdc.balanceOf(deployer.address);
        console.log("Deployer USDC balance:", ethers.formatUnits(deployerUSDCBalance, 6));
        
        if (deployerUSDCBalance >= currentDebt) {
          // Approve USDC spending for vault
          console.log("Approving USDC spending for full repayment...");
          const approveTx = await usdc.connect(deployer).approve(DEPLOYED_ADDRESSES.USDCVault, currentDebt);
          await approveTx.wait();
          console.log("✅ USDC approved for vault");
          
          // Repay full debt
          console.log("Repaying full debt...");
          const repayTx = await usdcVault.connect(deployer).repay(currentDebt);
          await repayTx.wait();
          console.log("✅ Full debt repaid successfully");
          
          // Check balances after full repayment
          console.log("\n=== AFTER FULL REPAYMENT ===");
          await printBalances(usdc, pawUSDC, lendingPool, deployer.address, "Deployer");
          await printSystemState(pawUSDC, lendingPool);
          
          // Check if collateral was returned
          const finalBorrowerPosition = await usdcVault.borrowers(deployer.address);
          console.log("\nFinal Borrower Position:");
          console.log("  Collateral Amount:", ethers.formatUnits(finalBorrowerPosition.collateralAmount, 18), "LP tokens");
          console.log("  Borrowed Amount:", ethers.formatUnits(finalBorrowerPosition.borrowedAmount, 6), "USDC");
          console.log("  Accrued Interest:", ethers.formatUnits(finalBorrowerPosition.accruedInterest, 6), "USDC");
          console.log("  Is Active:", finalBorrowerPosition.isActive);
          
          // Check LP token balance to confirm collateral return
          const finalLPBalance = await bubbleVault.balanceOf(deployer.address);
          console.log("Final LP Token balance:", ethers.formatUnits(finalLPBalance, 18));
          
        } else {
          console.log("❌ Insufficient USDC balance for full repayment");
          console.log("Need:", ethers.formatUnits(currentDebt, 6), "USDC");
          console.log("Have:", ethers.formatUnits(deployerUSDCBalance, 6), "USDC");
        }
      } catch (error) {
        console.log("❌ Full repayment failed:", error.message);
      }
    } else {
      console.log("ℹ️  No active borrowing position to fully repay");
    }

    // // ============================================================================
    // // TEST 6: SYSTEM ANALYTICS
    // // ============================================================================
    
    // console.log("\n=== TEST 6: SYSTEM ANALYTICS ===");
    
    // try {
    //   // Get vault TVL
    //   const vaultTVL = await usdcVault.getVaultTVL();
    //   console.log("Vault TVL:", ethers.formatUnits(vaultTVL, 6), "USDC");
      
    //   // Get vault yield generated
    //   const vaultYield = await usdcVault.getVaultYieldGenerated();
    //   console.log("Vault Yield Generated:", ethers.formatUnits(vaultYield, 6), "USDC");
      
    //   // Get total liquidated amount
    //   const totalLiquidated = await usdcVault.getTotalLiquidatedAmount();
    //   console.log("Total Liquidated Amount:", ethers.formatUnits(totalLiquidated, 6), "USDC");
      
    //   // Get protocol and vault fees
    //   const [protocolFees, vaultFees] = await usdcVault.getProtocolAndVaultfees();
    //   console.log("Protocol Fees:", ethers.formatUnits(protocolFees, 6), "USDC");
    //   console.log("Vault Fees:", ethers.formatUnits(vaultFees, 6), "USDC");
      
    //   // Get total interest distributed
    //   const totalInterestDistributed = await usdcVault.getTotalInterestDistributed();
    //   console.log("Total Interest Distributed:", ethers.formatUnits(totalInterestDistributed, 6), "USDC");
      
    //   // Get utilization rate
    //   const utilizationRate = await usdcVault.getUtilizationRate();
    //   console.log("Utilization Rate:", Number(utilizationRate) / 100, "%");
      
    //   // Get borrow rate
    //   const borrowRate = await usdcVault.getBorrowRate();
    //   console.log("Borrow Rate:", Number(borrowRate) / 100, "%");
      
    //   // Get supply rate
    //   const supplyRate = await usdcVault.getSupplyRate();
    //   console.log("Supply Rate:", Number(supplyRate) / 100, "%");
      
    // } catch (error) {
    //   console.log("❌ Analytics failed:", error.message);
    // }

    console.log("\n=== ALL TESTS COMPLETED ===");

  } catch (error) {
    console.error("Test failed:", error);
    throw error;
  }
}

// Helper function to print balances
async function printBalances(usdc, pawUSDC, lendingPool, userAddress, userName) {
  const usdcBalance = await usdc.balanceOf(userAddress);
  const usdcBalOfPaw = await usdc.balanceOf(await pawUSDC.getAddress());
  const pawUSDCBalance = await pawUSDC.balanceOf(userAddress);
  const underlyingBalance = await pawUSDC.getUnderlyingBalance(userAddress);
  
  console.log(`\n${userName} Balances:`);
  console.log(`  USDC: ${ethers.formatUnits(usdcBalance, 6)}`);
  console.log(`  PawUSDC: ${ethers.formatUnits(pawUSDCBalance, 6)}`);
  console.log(`  Underlying USDC: ${ethers.formatUnits(underlyingBalance, 6)}`);
  console.log(`  USDC in PawUSDC Contract: ${ethers.formatUnits(usdcBalOfPaw, 6)}`);
}

// Helper function to print system state
async function printSystemState(pawUSDC, lendingPool) {
  const exchangeRate = await pawUSDC.getExchangeRate();
  const totalUnderlying = await pawUSDC.getTotalUnderlying();
  const totalSupply = await pawUSDC.totalSupply();
  const totalDeposits = await lendingPool.getTotalDeposits();
  const totalBorrowed = await lendingPool.getTotalBorrowed();
  
  console.log(`\nSystem State:`);
  console.log(`  Exchange Rate: ${ethers.formatUnits(exchangeRate, 18)}`);
  console.log(`  Total Underlying: ${ethers.formatUnits(totalUnderlying, 6)} USDC`);
  console.log(`  Total PawUSDC Supply: ${ethers.formatUnits(totalSupply, 6)}`);
  console.log(`  Total Deposits: ${ethers.formatUnits(totalDeposits, 6)} USDC`);
  console.log(`  Total Borrowed: ${ethers.formatUnits(totalBorrowed, 6)} USDC`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 