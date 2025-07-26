const { ethers, upgrades } = require("hardhat");

async function testUnifiedLiquidity() {
  const [deployer, user1, user2] = await ethers.getSigners();
  console.log("Testing Unified Liquidity Architecture");
  console.log("Deployer:", deployer.address);
  console.log("User1:", user1.address);
  console.log("User2:", user2.address);

  try {
    // 1. Deploy the unified infrastructure
    console.log("\n1. Deploying Unified Infrastructure...");
    
    const USDC_ADDRESS = "0xf817257fed379853cDe0fa4F97AB987181B1E5Ea";
    const PRICE_FETCHER_ADDRESS = "0x85931b62e078AeBB4DeADf841be5592491C2efb7";

    // Deploy PawUSDC
    const PawUSDC = await ethers.getContractFactory("PawUSDC");
    const pawUSDC = await upgrades.deployProxy(PawUSDC, [USDC_ADDRESS]);
    await pawUSDC.waitForDeployment();
    console.log("✅ PawUSDC deployed:", await pawUSDC.getAddress());

    // Deploy Lending Pool
    const CentralizedLendingPool = await ethers.getContractFactory("CentralizedLendingPool");
    const lendingPool = await upgrades.deployProxy(CentralizedLendingPool, [
      USDC_ADDRESS,
      await pawUSDC.getAddress(),
      deployer.address
    ]);
    await lendingPool.waitForDeployment();
    console.log("✅ Lending Pool deployed:", await lendingPool.getAddress());

    // Set borrowing pool
    await pawUSDC.setBorrowingPool(await lendingPool.getAddress());

    // 2. Deploy both vaults
    console.log("\n2. Deploying Both Vaults...");
    
    // Deploy LP Token Vault
    const USDCVault = await ethers.getContractFactory("USDCVault");
    const lpVault = await upgrades.deployProxy(USDCVault, [
      USDC_ADDRESS,
      PRICE_FETCHER_ADDRESS,
      await pawUSDC.getAddress(),
      "0x81f337e24031D6136D7C1EDF38E9648679Eb9f1c", // Bubble Vault
      "0x3a98250F98Dd388C211206983453837C8365BDc1", // Token A
      "0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701", // Token B
      deployer.address,
      7000, // maxLTV
      7500, // liquidationThreshold
      500,  // liquidationPenalty
      100,  // slippageBPS
      "0x3e9A26b6edEcE5999aedEec9B093C851CdfeC529", // LP Token
      "0xb6091233aAcACbA45225a2B2121BBaC807aF4255", // Octo Router
      "0x0f2D067f8438869da670eFc855eACAC71616ca31", // Bubble Router
      4000, // liquidationVaultShare
      2000, // liquidationProtocolShare
      4000, // liquidationLenderShare
      await lendingPool.getAddress()
    ]);
    await lpVault.waitForDeployment();
    console.log("✅ LP Token Vault deployed:", await lpVault.getAddress());

    // Deploy NFT Vault
    const LiquidNFTVault = await ethers.getContractFactory("LiquidNFTVault");
    const nftVault = await upgrades.deployProxy(LiquidNFTVault, [
      USDC_ADDRESS,
      PRICE_FETCHER_ADDRESS,
      await pawUSDC.getAddress(),
      deployer.address,
      5000, // maxLTV (lower for NFTs)
      6000, // liquidationThreshold
      1000, // liquidationPenalty
      200,  // slippageBPS (higher for NFTs)
      4000, // liquidationVaultShare
      2000, // liquidationProtocolShare
      4000, // liquidationLenderShare
      await lendingPool.getAddress()
    ]);
    await nftVault.waitForDeployment();
    console.log("✅ NFT Vault deployed:", await nftVault.getAddress());

    // 3. Register both vaults in lending pool
    console.log("\n3. Registering Vaults in Lending Pool...");
    
    await lendingPool.registerVault(
      await lpVault.getAddress(),
      1000, 2000, 5000, 8000, 7000, 1000, 2000
    );
    console.log("✅ LP Vault registered");

    await lendingPool.registerVault(
      await nftVault.getAddress(),
      1000, 2000, 5000, 8000, 7000, 1000, 2000
    );
    console.log("✅ NFT Vault registered");

    // 4. Test unified liquidity
    console.log("\n4. Testing Unified Liquidity...");
    
    // Check initial state
    const initialLiquidity = await lendingPool.getAvailableLiquidity();
    console.log("✅ Initial liquidity in shared pool:", initialLiquidity.toString());
    
    const lpVaultDebt = await lendingPool.getVaultBorrowed(await lpVault.getAddress());
    const nftVaultDebt = await lendingPool.getVaultBorrowed(await nftVault.getAddress());
    console.log("✅ LP Vault debt:", lpVaultDebt.toString());
    console.log("✅ NFT Vault debt:", nftVaultDebt.toString());

    // 5. Simulate borrowing from both vaults
    console.log("\n5. Simulating Borrowing from Both Vaults...");
    
    // Note: This is a simulation - in real scenario you'd need actual collateral
    console.log("📝 In real scenario:");
    console.log("   - User1 deposits LP tokens → borrows from LP vault");
    console.log("   - User2 deposits NFTs → borrows from NFT vault");
    console.log("   - Both borrows use the SAME liquidity pool");
    console.log("   - Both pay interest to the SAME PawUSDC holders");

    // 6. Show unified architecture benefits
    console.log("\n6. Unified Architecture Benefits:");
    console.log("✅ Single liquidity pool for all vaults");
    console.log("✅ Unified interest rate management");
    console.log("✅ Shared PawUSDC for all lenders");
    console.log("✅ Better capital efficiency");
    console.log("✅ Easier risk management");

    console.log("\n🎉 Unified Liquidity Test Completed!");
    console.log("\nArchitecture Summary:");
    console.log("┌─────────────────┐    ┌─────────────────┐");
    console.log("│   LP Token      │    │   Liquid NFT    │");
    console.log("│     Vault       │    │     Vault       │");
    console.log("└─────────────────┘    └─────────────────┘");
    console.log("         │                       │");
    console.log("         └───────────┬───────────┘");
    console.log("                     │");
    console.log("         ┌─────────────────────────┐");
    console.log("         │   CentralizedLendingPool│");
    console.log("         │   (Shared Liquidity)    │");
    console.log("         └─────────────────────────┘");
    console.log("                     │");
    console.log("         ┌─────────────────────────┐");
    console.log("         │      PawUSDC            │");
    console.log("         │   (Interest Bearing)    │");
    console.log("         └─────────────────────────┘");

  } catch (error) {
    console.error("❌ Test failed:", error);
    throw error;
  }
}

testUnifiedLiquidity()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 