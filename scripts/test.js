const { ethers } = require("hardhat");

async function main() {
  // // Replace these addresses with the ones printed by your deploy.js
  // const PAWUSDC_ADDRESS = "0xCA7feFBC729f448Be69590a4857143bAC725b0fA";
  // const LENDING_POOL_ADDRESS = "0x64159ed1701680ff9c435B6b32AFCA25A2761118";
  // const VAULT_ADDRESS = "0xA483ff9A09e33cFc7b27F9C0959733e157cBed3b";

    // Replace these addresses with the ones printed by your deploy.js
    const PAWUSDC_ADDRESS = "0x095047eF801aE26404Fd79412FBe7C7504C91D04";
    const LENDING_POOL_ADDRESS = "0x18Cf1A5583cee3d85b1A493FBB8EfCf9E46D033c";
    const VAULT_ADDRESS = "0x6b37958AC680d668D7D87d356d95F72fB7c1808A";

  // Get deployer signer
  const [deployer] = await ethers.getSigners();
  console.log("Testing contracts with account:", deployer.address);

  // Attach to deployed contracts
  const pawUSDC = await ethers.getContractAt("PawUSDC", PAWUSDC_ADDRESS, deployer);
  const lendingPool = await ethers.getContractAt("CentralizedLendingPool", LENDING_POOL_ADDRESS, deployer);
  const vault = await ethers.getContractAt("USDCVault", VAULT_ADDRESS, deployer);

  // Get USDC contract instance
  const usdcAddress = await pawUSDC.usdc();
  console.log("USDC address:", usdcAddress);
  const usdc = await ethers.getContractAt("IERC20", usdcAddress, deployer);

  // Helper to print balances
  async function printBalances(label) {
    const usdcBal = await usdc.balanceOf(deployer.address);
    const pawUSDCBal = await pawUSDC.balanceOf(deployer.address);
    const usdcInPawUSDC = await usdc.balanceOf(await pawUSDC.getAddress());
    const pawinusdc=await pawUSDC.pawUSDCToUSDC(pawUSDCBal);
    console.log(`  PawUSDC in USDC: ${pawinusdc}`);
    const pawUsdcExchangeRate = await pawUSDC.exchangeRate();
    const pawUnderlying=await pawUSDC.totalUnderlying();
    console.log(`  PawUSDC underlying: ${pawUnderlying}`);

    const bubbleVaultAddress = await vault.bubbleVault();
    const bubbleVault = await ethers.getContractAt("IERC20", bubbleVaultAddress, deployer);
    const bubbleVaultBalance = await bubbleVault.balanceOf(deployer.address);
    const totalBorrow=await lendingPool.totalDeposits();
    console.log(`  Total borrow: ${totalBorrow}`);

    console.log(`\n[${label}] Balances:`);
    console.log(`  USDC:    ${ethers.formatUnits(usdcBal, 6)}`);
    console.log(`  PawUSDC: ${ethers.formatUnits(pawUSDCBal, 6)}`);
    console.log(`  PawUSDC exchange rate: ${pawUsdcExchangeRate}`);
    console.log(`  Bubble Vault balance: ${bubbleVaultBalance}`);
    console.log(`  USDC in PawUSDC: ${usdcInPawUSDC}`);
  }

  // // // 1. Lend USDC
  // await printBalances("Before Lend");
  // await printPawUSDCState("Before Lend");
  // try {
  //   const lendAmount = 1 * 1e6; // 1 USDC
  //   console.log("\n- Lending USDC:", lendAmount);
  //   await usdc.approve(await lendingPool.getAddress(), lendAmount);
  //   console.log("Approved USDC to lending pool");
  //   await vault.lendUSDC(lendAmount);
  //   console.log("✅ lendUSDC successful");
  //   await printBalances("After Lend");
  //   await printPawUSDCState("After Lend");
  // } catch (e) {
  //   console.log("❌ lendUSDC failed:", e.message);
  // }

  // 2. Withdraw USDC
  // await printBalances("Before Withdraw");
  // try {
  //   const withdrawAmount = 5316; // full USDC(0 means ful usdc)
  //   console.log("\n- Withdrawing USDC:", withdrawAmount);
  //   // Add this before the withdraw call
  //   const pawUSDCBalance = await pawUSDC.balanceOf(deployer.address);
  //   const exchangeRate = await pawUSDC.getExchangeRate();
  //   const maxWithdrawable = await pawUSDC.pawUSDCToUSDC(pawUSDCBalance);
  //   const totalUnderlying = await pawUSDC.getTotalUnderlying();
  //   const protocolUSDCBalance = await pawUSDC.protocolUSDCBalance();
  //   const usdcInPawUSDC = await usdc.balanceOf(await pawUSDC.getAddress());
  //   const totalDeposits = await lendingPool.totalDeposits();
  //   const totalBorrowed = await lendingPool.totalBorrowed();
  //   const maxUtilizationOnWithdraw = await lendingPool.maxUtilizationOnWithdraw();
  //   const redemptionFeeBps = await lendingPool.REDEMPTION_FEE_BPS();
  //   const basisPoints = await lendingPool.BASIS_POINTS();

  //   console.log("[DEBUG] lender:", deployer.address);
  //   console.log("[DEBUG] pawUSDCBalance:", pawUSDCBalance.toString());
  //   console.log("[DEBUG] exchangeRate:", exchangeRate.toString());
  //   console.log("[DEBUG] maxWithdrawable:", maxWithdrawable.toString());
  //   console.log("[DEBUG] totalUnderlying:", totalUnderlying.toString());
  //   console.log("[DEBUG] protocolUSDCBalance:", protocolUSDCBalance.toString());
  //   console.log("[DEBUG] usdcInPawUSDC:", usdcInPawUSDC.toString());
  //   console.log("[DEBUG] totalDeposits:", totalDeposits.toString());
  //   console.log("[DEBUG] totalBorrowed:", totalBorrowed.toString());
  //   console.log("[DEBUG] maxUtilizationOnWithdraw:", maxUtilizationOnWithdraw.toString());
  //   console.log("[DEBUG] redemptionFeeBps:", redemptionFeeBps.toString());
  //   console.log("[DEBUG] basisPoints:", basisPoints.toString());
  //   await vault.withdrawUSDC(withdrawAmount);
  //   console.log("✅ withdrawUSDC successful");
  //   await printBalances("After Withdraw");
  //   await printPawUSDCState("After Withdraw");
  // } catch (e) {
  //   console.log("❌ withdrawUSDC failed:", e.message);
  // }

  // 3. Borrow
  // await printBalances("Before Borrow");
  // await printPawUSDCState("Before Borrow");
  // try {
  //   //first from buble vault addres get balance of and take 0.1% of that
  //   const bubbleVaultAddress = await vault.bubbleVault();
  //   const bubbleVault = await ethers.getContractAt("IERC20", bubbleVaultAddress, deployer);
  //   const bubbleVaultBalance = await bubbleVault.balanceOf(deployer.address);
  //   const collateralAmount = bubbleVaultBalance * 1n / 1000n; // 0.1% of bubble vault balance
  //   //get colalateral value in usdc
  //   const collateralValueInUSDC = await vault.getCollateralValueInUSDC(collateralAmount);
  //   const borrowAmount = collateralValueInUSDC * 6n / 10n;// 60% of collateral value
  //   const borrow=await vault.borrowers(deployer.address);
  //   console.log("Borrower:", borrow);
  //   console.log("\n- Borrowing USDC (60% of collateral value):", borrowAmount, "with collateral:", collateralAmount);
  //   // Approve vault shares (mock)
  //   await bubbleVault.approve(await vault.getAddress(), collateralAmount);
  //   await vault.borrow(collateralAmount, borrowAmount);
  //   console.log("✅ borrow successful");
  //   await printBalances("After Borrow");
  //   await printPawUSDCState("After Borrow");
  // } catch (e) {
  //   console.log("❌ borrow failed:", e.message);
  // }

  // // 4. Repay
  // await printBalances("Before Repay");
  // await printPawUSDCState("Before Repay");
  // try {
  //   const currentDebt=await vault.getCurrentDebt(deployer.address);
  //   console.log("Borrower:", currentDebt);
  //   const borrow=await vault.borrowers(deployer.address);
  //   console.log("Borrower:", borrow);
  //   const repayAmount =currentDebt; // 50 USDC
  //   console.log("\n- Repaying USDC:", repayAmount);
  //   await usdc.approve(await vault.getAddress(), repayAmount);
  //   await vault.repay(repayAmount);
  //   console.log("✅ repay successful");
  //   await printBalances("After Repay");
  //   await printPawUSDCState("After Repay");
  //   console.log("Borrower after repay:", borrow);
  // } catch (e) {
  //   console.log("❌ repay failed:", e.message);
  // }

  // 5. Single Liquidation
  await printBalances("Before Single Liquidation");
  await printPawUSDCState("Before Single Liquidation");
  await vault.setSlippageBPS(1000);
  try {
    const firstLiquidatable = await vault.getFirstLiquidatablePosition();
    const config=await vault.config();
    const slippageBPS=config.slippageBPS;
    console.log("Slippage BPS:", slippageBPS);
    console.log("Config:", config);
    const octo=await vault.octoRouter();
    console.log("Octo Router:", octo);
   
    

    
    // Check token addresses
    const tokenA = await vault.tokenA();
    const tokenB = await vault.tokenB();
    const usdcAddr = await vault.usdc();
    const router = await vault.octoRouter();
    console.log("TokenA:", tokenA);
    console.log("TokenB:", tokenB);
    console.log("USDC:", usdcAddr);
    console.log("Router:", router);
    if (firstLiquidatable !== ethers.ZeroAddress) {
      console.log("\n- Liquidating:", firstLiquidatable);
      const borrow=await vault.borrowers(firstLiquidatable);
      console.log("Borrower:", borrow);
      const collateral=await vault.getCollateralValueInUSDC(borrow.collateralAmount);
      console.log("Collateral:", collateral);
      const debt=await vault.getCurrentDebt(firstLiquidatable);
  
      
      // Listen for debug events
      const liquidationTx = await vault.liquidate(firstLiquidatable);
      console.log("Liquidation Tx:", liquidationTx);
      const receipt = await liquidationTx.wait();
      console.log(receipt)
      
  
      
      console.log("✅ single liquidation successful");
      await printBalances("After Single Liquidation");
      await printPawUSDCState("After Single Liquidation");
    } else {
      console.log("No liquidatable positions for single liquidation");
    }
  } catch (e) {
    console.log("❌ single liquidation failed:", e.message);
    
    // Try to extract debug event from the error if possible
    if (e.receipt && e.receipt.logs) {
      try {
        const debugEvents = e.receipt.logs
          .map(log => {
            try {
              return vault.interface.parseLog({
                topics: log.topics,
                data: log.data
              });
            } catch (parseError) {
              return null;
            }
          })
          .filter(event => event && event.name === 'DebugLiquidation');
        
        if (debugEvents.length > 0) {
          const debugEvent = debugEvents[0];
          console.log("🔍 Debug Event Data (from failed transaction):");
          console.log("  usdcRecovered:", debugEvent.args[0].toString());
          console.log("  minExpectedUSDC:", debugEvent.args[1].toString());
          console.log("  expectedCollateralValue:", debugEvent.args[2].toString());
          console.log("  slippageBPS:", debugEvent.args[3].toString());
          console.log("  slippageCheckPassed:", debugEvent.args[4]);
        }
      } catch (parseError) {
        console.log("Could not parse debug events from error");
      }
    }
  }

  // 6. Batch Liquidation
  // await printBalances("Before Batch Liquidation");
  // try {
  //   const batch = await vault.getLiquidatablePositions(5);
  //   if (batch.length > 0) {
  //     console.log("\n- Batch liquidating:", batch);
  //     await vault.liquidateMultiple(batch);
  //     console.log("✅ batch liquidation successful");
  //     await printBalances("After Batch Liquidation");
  //   } else {
  //     console.log("No liquidatable positions for batch liquidation");
  //   }
  // } catch (e) {
  //   console.log("❌ batch liquidation failed:", e.message);
  // }

  // 7. Gelato Checker Functions
  // try {
  //   const [canExec, execPayload] = await vault.checker();
  //   console.log("\n- Gelato checker (batch): canExec=", canExec, ", execPayload=", execPayload);
  //   const [canExecSingle, execPayloadSingle] = await vault.checkerSingle();
  //   console.log("- Gelato checker (single): canExec=", canExecSingle, ", execPayload=", execPayloadSingle);
  //   const count = await vault.getLiquidatableCount();
  //   console.log("- Liquidatable count:", count.toString());
  //   const needed = await vault.liquidationsNeeded();
  //   console.log("- Liquidations needed:", needed);
  // } catch (e) {
  //   console.log("❌ Gelato checker functions failed:", e.message);
  // }

  async function printPawUSDCState(label) {
    const protocolUSDCBalance = await pawUSDC.protocolUSDCBalance();
    const totalUnderlying = await pawUSDC.getTotalUnderlying();
    const totalRedemptionFees = await pawUSDC.getTotalRedemptionFees();
    const usdcInPawUSDC = await usdc.balanceOf(await pawUSDC.getAddress());
    console.log(`\n[DEBUG][${label}]`);
    console.log("protocolUSDCBalance:", protocolUSDCBalance.toString());
    console.log("totalUnderlying:", totalUnderlying.toString());
    console.log("totalRedemptionFees:", totalRedemptionFees.toString());
    console.log("usdcInPawUSDC:", usdcInPawUSDC.toString());
    console.log("protocolUSDCBalance + totalRedemptionFees:", BigInt(protocolUSDCBalance) + BigInt((totalRedemptionFees).toString()));
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 