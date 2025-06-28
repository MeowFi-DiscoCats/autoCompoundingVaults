const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  // Contract addresses from PawUSDC.sol comments
  const USDC_ADDRESS = "0xf817257fed379853cDe0fa4F97AB987181B1E5Ea";
  const TOKEN_A_ADDRESS = "0x3a98250F98Dd388C211206983453837C8365BDc1"; // SHMON
  const TOKEN_B_ADDRESS = "0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701"; // WMON
  const BUBBLE_VAULT_ADDRESS = "0x81f337e24031D6136D7C1EDF38E9648679Eb9f1c";
  const BUBBLE_ROUTER_ADDRESS = "0x0f2D067f8438869da670eFc855eACAC71616ca31";
  const LP_TOKEN_ADDRESS = "0x3e9A26b6edEcE5999aedEec9B093C851CdfeC529";
  const PRICE_FETCHER_ADDRESS = "0x85931b62e078AeBB4DeADf841be5592491C2efb7";
  const OCTO_ROUTER_ADDRESS = "0xb6091233aAcACbA45225a2B2121BBaC807aF4255";

  // Configuration values from PawUSDC.sol comments
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

  try {
    // 1. Deploy and Initialize PawUSDC
    console.log("\n1. Deploying and Initializing PawUSDC...");
    const PawUSDC = await ethers.getContractFactory("PawUSDC");
    const pawUSDC = await PawUSDC.deploy();
    await pawUSDC.waitForDeployment();
    console.log("PawUSDC deployed to:", await pawUSDC.getAddress());

    // Initialize PawUSDC
    await pawUSDC.initialize(USDC_ADDRESS);
    console.log("PawUSDC initialized with USDC address:", USDC_ADDRESS);

    // 2. Deploy Lending Pool (simplified initialization)
    console.log("\n2. Deploying CentralizedLendingPool...");
    const CentralizedLendingPool = await ethers.getContractFactory("CentralizedLendingPool");
    const lendingPool = await CentralizedLendingPool.deploy(
      USDC_ADDRESS,
      await pawUSDC.getAddress(),
      deployer.address // owner
    );
    await lendingPool.waitForDeployment();
    console.log("CentralizedLendingPool deployed to:", await lendingPool.getAddress());

    // Set borrowing pool in PawUSDC
    await pawUSDC.setBorrowingPool(await lendingPool.getAddress());
    console.log("Set borrowing pool in PawUSDC:", await lendingPool.getAddress());

    // 3. Deploy USDC Vault Implementation (for proxy pattern)
    console.log("\n3. Deploying USDC Vault Implementation...");
    const USDCVault = await ethers.getContractFactory("USDCVault");
    const usdcVaultImpl = await USDCVault.deploy();
    await usdcVaultImpl.waitForDeployment();
    console.log("USDC Vault Implementation deployed to:", await usdcVaultImpl.getAddress());

    // 4. Deploy Factory
    console.log("\n4. Deploying USDCVaultFactory...");
    const USDCVaultFactory = await ethers.getContractFactory("USDCVaultFactory");
    const usdcVaultFactory = await USDCVaultFactory.deploy(await usdcVaultImpl.getAddress());
    await usdcVaultFactory.waitForDeployment();
    console.log("USDCVaultFactory deployed to:", await usdcVaultFactory.getAddress());

    // 5. Create Vault via Factory
    console.log("\n5. Creating Vault via Factory...");
    
    // Create vault through factory with direct parameters
    const createVaultTx = await usdcVaultFactory.createVault(
      "USDC Vault", // name
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
      await lendingPool.getAddress()
    );
    const createVaultReceipt = await createVaultTx.wait();
    
    // Get the created vault address from the factory
    const vaults = await usdcVaultFactory.getVaults();
    const createdVaultAddress = vaults[0];
    console.log("Vault created via factory at:", createdVaultAddress);

    // 6. Register Vault in Lending Pool (with interest rate parameters)
    console.log("\n6. Registering Vault in Lending Pool...");
    await lendingPool.registerVault(
      createdVaultAddress,
      CONFIG.baseRate,
      CONFIG.multiplier,
      CONFIG.jumpMultiplier,
      CONFIG.kink,
      CONFIG.lenderShare,
      CONFIG.vaultFeeRate,
      CONFIG.protocolFeeRate
    );
    console.log("Vault registered in lending pool with interest rate configuration");

    // 7. Set up additional configurations for the created vault
    console.log("\n7. Setting up additional configurations...");
    
    // Get the vault instance
    const createdVault = await ethers.getContractAt("USDCVault", createdVaultAddress);
    
    // Check vault ownership
    const vaultOwner = await createdVault.owner();
    console.log("Vault owner:", vaultOwner);
    console.log("Deployer address:", deployer.address);
    
    if (vaultOwner === deployer.address) {
      // Set fee recipients
      await createdVault.setProtocolFeeRecipient(deployer.address);
      await createdVault.setVaultFeeRecipient(deployer.address);
      console.log("Set fee recipients in created vault");
    } else {
      console.log("⚠️  Vault is not owned by deployer. Fee recipients cannot be set automatically.");
      console.log("You may need to transfer ownership or set fee recipients manually.");
    }

    // 8. Print deployment summary
    console.log("\n=== DEPLOYMENT SUMMARY ===");
    console.log("Network:", network.name);
    console.log("Deployer:", deployer.address);
    console.log("\nContract Addresses:");
    console.log("PawUSDC:", await pawUSDC.getAddress());
    console.log("CentralizedLendingPool:", await lendingPool.getAddress());
    console.log("USDC Vault Implementation:", await usdcVaultImpl.getAddress());
    console.log("USDCVaultFactory:", await usdcVaultFactory.getAddress());
    console.log("Created Vault (Proxy):", createdVaultAddress);
    
    console.log("\nConfiguration:");
    console.log("Max LTV:", CONFIG.maxLTV / 100, "%");
    console.log("Liquidation Threshold:", CONFIG.liquidationThreshold / 100, "%");
    console.log("Liquidation Penalty:", CONFIG.liquidationPenalty / 100, "%");
    console.log("Slippage BPS:", CONFIG.slippageBPS);
    console.log("Protocol Fee Rate:", CONFIG.protocolFeeRate / 100, "%");
    console.log("Vault Fee Rate:", CONFIG.vaultFeeRate / 100, "%");

    console.log("\nExternal Addresses:");
    console.log("USDC:", USDC_ADDRESS);
    console.log("Token A (SHMON):", TOKEN_A_ADDRESS);
    console.log("Token B (WMON):", TOKEN_B_ADDRESS);
    console.log("Bubble Vault:", BUBBLE_VAULT_ADDRESS);
    console.log("Bubble Router:", BUBBLE_ROUTER_ADDRESS);
    console.log("LP Token:", LP_TOKEN_ADDRESS);
    console.log("Price Fetcher:", PRICE_FETCHER_ADDRESS);
    console.log("Octo Router:", OCTO_ROUTER_ADDRESS);

    console.log("\nDeployment completed successfully!");

  } catch (error) {
    console.error("Deployment failed:", error);
    throw error;
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 