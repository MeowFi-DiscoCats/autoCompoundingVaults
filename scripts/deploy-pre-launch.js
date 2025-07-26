const { ethers, upgrades } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);
  console.log(
    "Account balance:",
    (await ethers.provider.getBalance(deployer.address)).toString()
  );

  // Contract addresses from PawUSDC.sol comments
  const USDC_ADDRESS = "0xf817257fed379853cDe0fa4F97AB987181B1E5Ea";
  const TOKEN_A_ADDRESS = "0x3a98250F98Dd388C211206983453837C8365BDc1"; // SHMON
  const TOKEN_B_ADDRESS = "0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701"; // WMON
  const BUBBLE_VAULT_ADDRESS = "0x81f337e24031D6136D7C1EDF38E9648679Eb9f1c";
  const BUBBLE_ROUTER_ADDRESS = "0x0f2D067f8438869da670eFc855eACAC71616ca31";
  const LP_TOKEN_ADDRESS = "0x3e9A26b6edEcE5999aedEec9B093C851CdfeC529";
  const PRICE_FETCHER_ADDRESS = "0x85931b62e078AeBB4DeADf841be5592491C2efb7";
  const OCTO_ROUTER_ADDRESS = "0xb6091233aAcACbA45225a2B2121BBaC807aF4255";

  // Configuration values
  const CONFIG = {
    maxLTV: 7000, // 70%
    liquidationThreshold: 7500, // 75%
    liquidationPenalty: 500, // 5%
    baseRate: 1000, // 10%
    multiplier: 2000, // 20%
    jumpMultiplier: 5000, // 50%
    kink: 8000, // 80%
    protocolFeeRate: 2000, // 20%
    vaultFeeRate: 1000, // 10%
    lenderShare: 7000, // 70%
    slippageBPS: 100, // 1%
    liquidationVaultShare: 4000, // 40%
    liquidationProtocolShare: 2000, // 20%
    liquidationLenderShare: 4000, // 40%
  };

  // Set launch timestamp (5 minutes from now for testing)
  const now = Math.floor(Date.now() / 1000);
  const launchTimestamp = now + (5 * 60); // 5 minutes from now
  console.log("Launch timestamp set to:", new Date(launchTimestamp * 1000).toISOString());

  try {
    // 1. Deploy and Initialize PawUSDC as ERC-1967 Proxy
    console.log("\n1. Deploying and Initializing PawUSDC as ERC-1967 Proxy...");
    const PawUSDC = await ethers.getContractFactory("PawUSDC");

    // Deploy PawUSDC as upgradeable proxy
    const pawUSDC = await upgrades.deployProxy(PawUSDC, [USDC_ADDRESS]);
    await pawUSDC.waitForDeployment();
    console.log(
      "✅ PawUSDC (ERC-1967 Proxy) deployed to:",
      await pawUSDC.getAddress()
    );
    console.log("✅ PawUSDC initialized with USDC address:", USDC_ADDRESS);

    // 2. Deploy Lending Pool (Upgradeable - for interest rate models and features)
    console.log("\n2. Deploying CentralizedLendingPool as ERC-1967 Proxy...");
    const CentralizedLendingPool = await ethers.getContractFactory(
      "CentralizedLendingPool"
    );

    // Deploy lending pool as upgradeable proxy with launch timestamp
    const lendingPool = await upgrades.deployProxy(CentralizedLendingPool, [
      USDC_ADDRESS,
      await pawUSDC.getAddress(),
      deployer.address, // owner
      launchTimestamp, // launch timestamp
    ]);
    await lendingPool.waitForDeployment();
    console.log(
      "✅ CentralizedLendingPool (ERC-1967 Proxy) deployed to:",
      await lendingPool.getAddress()
    );

    // Set borrowing pool in PawUSDC
    await pawUSDC.setBorrowingPool(await lendingPool.getAddress());
    console.log(
      "✅ Set borrowing pool in PawUSDC:",
      await lendingPool.getAddress()
    );

    // 3. Deploy USDC Vault as ERC-1967 Upgradeable Proxy
    console.log("\n3. Deploying USDC Vault as ERC-1967 Upgradeable Proxy...");
    const USDCVault = await ethers.getContractFactory("USDCVault");

    // Deploy proxy with implementation
    const vault = await upgrades.deployProxy(USDCVault, [
      USDC_ADDRESS,
      PRICE_FETCHER_ADDRESS,
      await pawUSDC.getAddress(),
      BUBBLE_VAULT_ADDRESS,
      TOKEN_A_ADDRESS,
      TOKEN_B_ADDRESS,
      deployer.address, // vaultOwner
      CONFIG.maxLTV,
      CONFIG.liquidationThreshold,
      CONFIG.liquidationPenalty,
      CONFIG.slippageBPS,
      LP_TOKEN_ADDRESS,
      OCTO_ROUTER_ADDRESS,
      BUBBLE_ROUTER_ADDRESS,
      CONFIG.liquidationVaultShare,
      CONFIG.liquidationProtocolShare,
      CONFIG.liquidationLenderShare,
      await lendingPool.getAddress(),
    ]);

    await vault.waitForDeployment();
    console.log(
      "✅ USDC Vault (ERC-1967 Proxy) deployed to:",
      await vault.getAddress()
    );

    // 4. Register Vault in Lending Pool (with interest rate parameters)
    console.log("\n4. Registering Vault in Lending Pool...");
    await lendingPool.registerVault(
      await vault.getAddress(),
      CONFIG.baseRate,
      CONFIG.multiplier,
      CONFIG.jumpMultiplier,
      CONFIG.kink,
      CONFIG.lenderShare,
      CONFIG.vaultFeeRate,
      CONFIG.protocolFeeRate
    );
    console.log(
      "✅ Vault registered in lending pool with interest rate configuration"
    );

    // 5. Set up additional configurations for the vault
    console.log("\n5. Setting up additional configurations...");

    // Check vault ownership
    const vaultOwner = await vault.owner();
    console.log("✅ Vault owner:", vaultOwner);
    console.log("✅ Deployer address:", deployer.address);

    if (vaultOwner === deployer.address) {
      // Set fee recipients
      await vault.setProtocolFeeRecipient(deployer.address);
      await vault.setVaultFeeRecipient(deployer.address);
      await vault.setVaultHardcodedYield(1200);
      await vault.setLiquidationsPaused(false);
      await vault.setBorrowingPaused(false);
      await vault.setLiquidationEnabled(true);
      console.log("✅ Set fee recipients in vault");
    } else {
      console.log(
        "⚠️  Vault is not owned by deployer. Fee recipients cannot be set automatically."
      );
      console.log(
        "You may need to transfer ownership or set fee recipients manually."
      );
    }

    // 6. Print deployment summary
    console.log("\n=== DEPLOYMENT SUMMARY ===");
    console.log("Network:", network.name);
    console.log("Deployer:", deployer.address);
    console.log("\nContract Addresses:");
    console.log("✅ PawUSDC (ERC-1967 Proxy):", await pawUSDC.getAddress());
    console.log(
      "✅ CentralizedLendingPool (ERC-1967 Proxy):",
      await lendingPool.getAddress()
    );
    console.log("✅ USDC Vault (ERC-1967 Proxy):", await vault.getAddress());

    console.log("\nConfiguration:");
    console.log("✅ Max LTV:", CONFIG.maxLTV / 100, "%");
    console.log(
      "✅ Liquidation Threshold:",
      CONFIG.liquidationThreshold / 100,
      "%"
    );
    console.log(
      "✅ Liquidation Penalty:",
      CONFIG.liquidationPenalty / 100,
      "%"
    );
    console.log("✅ Slippage BPS:", CONFIG.slippageBPS);
    console.log("✅ Protocol Fee Rate:", CONFIG.protocolFeeRate / 100, "%");
    console.log("✅ Vault Fee Rate:", CONFIG.vaultFeeRate / 100, "%");

    console.log("\n=== PRE-LAUNCH SYSTEM ===");
    console.log("✅ Launch Timestamp:", new Date(launchTimestamp * 1000).toISOString());
    console.log("✅ Pre-launch deposits enabled until launch");
    console.log("✅ Users can call vault.preLaunchDeposit(amount) to queue deposits");
    console.log("✅ Users can call vault.preLaunchWithdraw(amount) to withdraw before launch");
    console.log("✅ After launch, call lendingPool.activateLaunch()");
    console.log("✅ Then call lendingPool.processPreLaunchDeposits() to mint PawUSDC");

    console.log("\n🎉 Pre-launch deployment completed successfully!");
  } catch (error) {
    console.error("❌ Deployment failed:", error);
    throw error;
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 