const { ethers } = require("hardhat");

async function main() {
  // Replace these addresses with the ones printed by your deploy.js
  const PAWUSDC_ADDRESS = "0xCA7feFBC729f448Be69590a4857143bAC725b0fA";
  const LENDING_POOL_ADDRESS = "0x64159ed1701680ff9c435B6b32AFCA25A2761118";
  const VAULT_ADDRESS = "0xA483ff9A09e33cFc7b27F9C0959733e157cBed3b";

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
  // try {
  //   const lendAmount = 1 * 1e6; // 1 USDC
  //   console.log("\n- Lending USDC:", lendAmount);
  //   await usdc.approve(await lendingPool.getAddress(), lendAmount);
  //   console.log("Approved USDC to lending pool");
  //   await vault.lendUSDC(lendAmount);
  //   console.log("✅ lendUSDC successful");
  //   await printBalances("After Lend");
  // } catch (e) {
  //   console.log("❌ lendUSDC failed:", e.message);
  // }

  // // 2. Withdraw USDC
  await printBalances("Before Withdraw");
  try {
    const withdrawAmount = 1 * 1e6; // full USDC
    console.log("\n- Withdrawing USDC:", withdrawAmount);
    await vault.withdrawUSDC(withdrawAmount);
    console.log("✅ withdrawUSDC successful");
    await printBalances("After Withdraw");
  } catch (e) {
    console.log("❌ withdrawUSDC failed:", e.message);
  }

  // 3. Borrow
  // await printBalances("Before Borrow");
  // try {
  //   //first from buble vault addres get balance of and take 0.1% of that
  //   const bubbleVaultAddress = await vault.bubbleVault();
  //   const bubbleVault = await ethers.getContractAt("IERC20", bubbleVaultAddress, deployer);
  //   const bubbleVaultBalance = await bubbleVault.balanceOf(deployer.address);
  //   const collateralAmount = bubbleVaultBalance * 1n / 1000n; // 0.1% of bubble vault balance
  //   //get colalateral value in usdc
  //   const collateralValueInUSDC = await vault.getCollateralValueInUSDC(collateralAmount);
  //   const borrowAmount = collateralValueInUSDC * 6n / 10n;// 60% of collateral value
  //   console.log("\n- Borrowing USDC:", borrowAmount, "with collateral:", collateralAmount);
  //   // Approve vault shares (mock)
  //   await bubbleVault.approve(await vault.getAddress(), collateralAmount);
  //   await vault.borrow(collateralAmount, borrowAmount);
  //   console.log("✅ borrow successful");
  //   await printBalances("After Borrow");
  // } catch (e) {
  //   console.log("❌ borrow failed:", e.message);
  // }

  // // 4. Repay
  // await printBalances("Before Repay");
  // try {
  //   const currentDebt=await vault.getCurrentDebt(deployer.address);
  //   console.log("Borrower:", currentDebt);
  //   const repayAmount =currentDebt; // 50 USDC
  //   console.log("\n- Repaying USDC:", repayAmount);
  //   await usdc.approve(await vault.getAddress(), repayAmount);
  //   await vault.repay(repayAmount);
  //   console.log("✅ repay successful");
  //   await printBalances("After Repay");
  // } catch (e) {
  //   console.log("❌ repay failed:", e.message);
  // }

  // 5. Single Liquidation
  // await printBalances("Before Single Liquidation");
  // try {
  //   const firstLiquidatable = await vault.getFirstLiquidatablePosition();
  //   if (firstLiquidatable !== ethers.constants.AddressZero) {
  //     console.log("\n- Liquidating:", firstLiquidatable);
  //     await vault.liquidate(firstLiquidatable);
  //     console.log("✅ single liquidation successful");
  //     await printBalances("After Single Liquidation");
  //   } else {
  //     console.log("No liquidatable positions for single liquidation");
  //   }
  // } catch (e) {
  //   console.log("❌ single liquidation failed:", e.message);
  // }

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
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 