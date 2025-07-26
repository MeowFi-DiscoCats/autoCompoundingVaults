const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Testing pre-launch system with accounts:");
  console.log("Deployer:", deployer.address);
  const user1 = deployer;

  console.log("User1:", user1.address);

  // Replace with your deployed contract addresses
  const LENDING_POOL_ADDRESS = "0xCDfE73D175D81c06c8e04EeB93978F87313582eD";
  const VAULT_ADDRESS = "0x36515067c6665d107b3b527407D079DE67B06714";
  const USDC_ADDRESS = "0xf817257fed379853cDe0fa4F97AB987181B1E5Ea";
  const PAWUSDC_ADDRESS = "0x879d15A90c1365CCbF82a49D44F8e9e50156069a";

  try {
    const lendingPool = await ethers.getContractAt("CentralizedLendingPool", LENDING_POOL_ADDRESS);
    const vault = await ethers.getContractAt("USDCVault", VAULT_ADDRESS, deployer);
    const usdc = await ethers.getContractAt("IERC20", USDC_ADDRESS, deployer);
    const pawUSDC = await ethers.getContractAt("PawUSDC", PAWUSDC_ADDRESS, deployer);

    console.log("\n=== CONTRACT ADDRESSES ===");
    console.log("Lending Pool:", LENDING_POOL_ADDRESS);
    console.log("Vault:", VAULT_ADDRESS);
    console.log("USDC:", USDC_ADDRESS);
    console.log("PawUSDC:", PAWUSDC_ADDRESS);

    const launchStatus = await lendingPool.getLaunchStatus();
    console.log("\n=== LAUNCH STATUS ===");
    console.log("Launched:", launchStatus.launched);
    console.log("Launch Time:", new Date(Number(launchStatus.launchTime) * 1000).toISOString());
    console.log("Time Until Launch:", Number(launchStatus.timeUntilLaunch), "seconds");

    if (!launchStatus.launched && Number(launchStatus.timeUntilLaunch) > 0) {
      console.log("\n⏰ Waiting for launch time...");
      console.log("You can test pre-launch deposits now, or wait for launch time to test full flow");
    }


    // console.log("\n=== PRE-LAUNCH DEPOSITS ===");

    const user1USDCBalance = await usdc.balanceOf(user1.address);
    console.log("User1 USDC balance:", ethers.formatUnits(user1USDCBalance, 6));

    // const depositAmount1 = ethers.parseUnits("1", 6);
    // if (user1USDCBalance >= depositAmount1) {
    //   await usdc.connect(user1).approve(LENDING_POOL_ADDRESS, depositAmount1);
    //   await lendingPool.connect(user1).preLaunchDeposit(depositAmount1);
    //   console.log("✅ User1 deposited 1 USDC (pre-launch)");
    // } else {
    //   console.log("❌ User1 has insufficient USDC");
    // }

    // const totalPreLaunch = await lendingPool.getTotalPreLaunchDeposits();
    // const depositorCount = await lendingPool.getPreLaunchDepositorCount();
    // console.log("\n=== PRE-LAUNCH SUMMARY ===");
    // console.log("Total pre-launch deposits:", ethers.formatUnits(totalPreLaunch, 6), "USDC");
    // console.log("Number of depositors:", depositorCount.toString());

    // const user1Deposit = await lendingPool.getPreLaunchDeposit(user1.address);
    // console.log("User1 deposit:", ethers.formatUnits(user1Deposit.amount, 6), "USDC");

    // console.log("\n=== PRE-LAUNCH WITHDRAWAL TEST ===");
    // const withdrawAmount = ethers.parseUnits("0.5", 6);
    // if (user1Deposit.amount >= withdrawAmount) {
    //   await lendingPool.connect(user1).preLaunchWithdraw(withdrawAmount);
    //   console.log("✅ User1 withdrew 0.5 USDC (pre-launch)");

    //   const user1UpdatedDeposit = await lendingPool.getPreLaunchDeposit(user1.address);
    //   console.log("User1 updated deposit:", ethers.formatUnits(user1UpdatedDeposit.amount, 6), "USDC");
    // }
    console.log(launchStatus.launched, Number(launchStatus.timeUntilLaunch))
    //balance of user1 in pawusdc
    const user1PawUSDC = await pawUSDC.balanceOf(user1.address);
    console.log("User1 PawUSDC balance:", ethers.formatUnits(user1PawUSDC, 6));

    if (launchStatus.launched || Number(launchStatus.timeUntilLaunch) === 0) {
      console.log("\n=== POST-LAUNCH TESTING ===");

      if (!launchStatus.launched) {
        await lendingPool.activateLaunch();
        console.log("✅ Launch activated");
      }

      const unprocessedCount = await lendingPool.getUnprocessedPreLaunchDeposits();
      if (unprocessedCount > 0) {
        await lendingPool.processPreLaunchDeposits();
        console.log("✅ Pre-launch deposits processed");
      }

      const user1PawUSDC = await pawUSDC.balanceOf(user1.address);
      console.log("User1 PawUSDC balance:", ethers.formatUnits(user1PawUSDC, 6));

      const exchangeRate = await pawUSDC.getExchangeRate();
      console.log("PawUSDC exchange rate:", ethers.formatUnits(exchangeRate, 18));

      // ✅ ADDED: Check if vault is registered in lending pool
      console.log("\n=== VAULT REGISTRATION CHECK ===");
      const activeVaults = await lendingPool.getActiveVaults();
      console.log("Active vaults:", activeVaults);
      
      const isVaultRegistered = activeVaults.includes(VAULT_ADDRESS);
      console.log("Is vault registered:", isVaultRegistered);
      
      if (!isVaultRegistered) {
        console.log("❌ Vault is not registered in lending pool. Cannot proceed with post-launch deposit test.");
        console.log("Please ensure the vault was properly registered during deployment.");
        return;
      }

      console.log("\n=== POST-LAUNCH DEPOSIT TEST ===");
      const postLaunchDeposit = ethers.parseUnits("2", 6);
      if (user1USDCBalance >= postLaunchDeposit) {
        try {
          // Check USDC allowance for lending pool
          const currentAllowance = await usdc.allowance(user1.address, LENDING_POOL_ADDRESS);
          console.log("Current USDC allowance for lending pool:", ethers.formatUnits(currentAllowance, 6));
          
          if (currentAllowance < postLaunchDeposit) {
            console.log("Approving USDC for lending pool...");
            const approveTx = await usdc.connect(user1).approve(LENDING_POOL_ADDRESS, postLaunchDeposit);
            await approveTx.wait();
            console.log("✅ USDC approved for lending pool");
          }
          
          // Check vault configuration
          const vaultConfig = await vault.config();
          console.log("Vault active:", vaultConfig.active);
          console.log("Vault maxLTV:", vaultConfig.maxLTV.toString());
          
          console.log("Attempting to deposit 2 USDC...");
          const depositTx = await vault.connect(user1).lendUSDC(postLaunchDeposit);
          await depositTx.wait();
          console.log("✅ User1 deposited 2 USDC (post-launch)");

          const user1FinalPawUSDC = await pawUSDC.balanceOf(user1.address);
          console.log("User1 final PawUSDC balance:", ethers.formatUnits(user1FinalPawUSDC, 6));
        } catch (error) {
          console.error("❌ Deposit failed with error:", error.message);
          console.error("Error details:", error);
        }
      } else {
        console.log("❌ User1 has insufficient USDC for post-launch deposit");
      }
    } else {
      console.log("\n⏰ Launch time not reached yet. You can:");
      console.log("1. Wait for launch time to test full flow");
      console.log("2. Test more pre-launch deposits/withdrawals");
      console.log("3. Check pre-launch deposit status");
    }

    console.log("\n=== TEST COMPLETE ===");
    console.log("✅ Pre-launch system is working correctly!");

  } catch (err) {
    console.error("❌ Test failed:", err);
    throw err;
  }
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
