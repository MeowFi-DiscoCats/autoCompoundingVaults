const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Checking ownership with account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  // Replace with your actual PawUSDC contract address
  const PAW_USDC_ADDRESS = "0xCA7feFBC729f448Be69590a4857143bAC725b0fA"; // Replace with your deployed PawUSDC address
  
  if (PAW_USDC_ADDRESS === "0xCA7feFBC729f448Be69590a4857143bAC725b0fA") {
    console.log("❌ Please replace PAW_USDC_ADDRESS with your actual PawUSDC contract address");
    return;
  }

  try {
    // Get the PawUSDC contract instance
    const PawUSDC = await ethers.getContractFactory("PawUSDC");
    const pawUSDC = PawUSDC.attach(PAW_USDC_ADDRESS);

    console.log("\n=== PAWUSDC OWNERSHIP CHECK ===");
    console.log("Contract Address:", PAW_USDC_ADDRESS);

    // Check current owner
    const currentOwner = await pawUSDC.owner();
    console.log("Current Owner:", currentOwner);
    console.log("Deployer Address:", deployer.address);
    console.log("Is Deployer Owner:", currentOwner === deployer.address);

    // Check borrowing pool
    const borrowingPool = await pawUSDC.borrowingPool();
    console.log("Borrowing Pool:", borrowingPool);

    // Check USDC address
    const usdcAddress = await pawUSDC.usdc();
    console.log("USDC Address:", usdcAddress);

    // Check exchange rate and other key parameters
    const exchangeRate = await pawUSDC.exchangeRate();
    const totalUnderlying = await pawUSDC.totalUnderlying();
    const totalSupply = await pawUSDC.totalSupply();
    const protocolUSDCBalance = await pawUSDC.protocolUSDCBalance();

    console.log("\n=== CONTRACT STATE ===");
    console.log("Exchange Rate:", ethers.formatUnits(exchangeRate, 18));
    console.log("Total Underlying USDC:", ethers.formatUnits(totalUnderlying, 6));
    console.log("Total PawUSDC Supply:", ethers.formatUnits(totalSupply, 6));
    console.log("Protocol USDC Balance:", ethers.formatUnits(protocolUSDCBalance, 6));

    // If deployer is not the owner, show warning
    if (currentOwner !== deployer.address) {
      console.log("\n⚠️  WARNING: Deployer is not the current owner!");
      console.log("You cannot transfer ownership unless you are the current owner.");
      console.log("Current owner needs to call transferOwnership() to change ownership.");
      return;
    }

    // Show ownership transfer options
    console.log("\n=== OWNERSHIP TRANSFER OPTIONS ===");
    console.log("Since you are the current owner, you can:");
    console.log("1. Transfer ownership to another address");
    console.log("2. Renounce ownership (set to address(0))");
    
    // Example of how to transfer ownership (commented out for safety)
    console.log("\n=== EXAMPLE COMMANDS (UNCOMMENT TO USE) ===");
    console.log("// Transfer ownership to a new address:");
    console.log("// await pawUSDC.transferOwnership('0xNewOwnerAddress');");
    console.log("");
    console.log("// Renounce ownership:");
    console.log("// await pawUSDC.renounceOwnership();");

    // Uncomment the lines below if you want to actually transfer ownership
    
    // Example: Transfer ownership to a new address
    const newOwnerAddress = "0x7d5F37a131578a60f190500EB521AA2F2745f77c"; // Replace with new owner address
    if (newOwnerAddress !== "0x7d5F37a131578a60f190500EB521AA2F2745f77c") {
      console.log("\n🔄 Transferring ownership to:", newOwnerAddress);
      const tx = await pawUSDC.transferOwnership(newOwnerAddress);
      await tx.wait();
      console.log("✅ Ownership transferred successfully!");
      
      // Verify the transfer
      const newOwner = await pawUSDC.owner();
      console.log("New Owner:", newOwner);
    }
    

  } catch (error) {
    console.error("❌ Error:", error);
    throw error;
  }
}

// Function to transfer ownership (separate function for safety)
async function transferOwnership() {
  const [deployer] = await ethers.getSigners();
  console.log("Transferring ownership with account:", deployer.address);

  // Replace with your actual addresses
  const PAW_USDC_ADDRESS = "0x..."; // Replace with your deployed PawUSDC address
  const NEW_OWNER_ADDRESS = "0x..."; // Replace with new owner address

  if (PAW_USDC_ADDRESS === "0x..." || NEW_OWNER_ADDRESS === "0x...") {
    console.log("❌ Please replace PAW_USDC_ADDRESS and NEW_OWNER_ADDRESS with actual addresses");
    return;
  }

  try {
    const PawUSDC = await ethers.getContractFactory("PawUSDC");
    const pawUSDC = PawUSDC.attach(PAW_USDC_ADDRESS);

    // Check current owner
    const currentOwner = await pawUSDC.owner();
    console.log("Current Owner:", currentOwner);
    console.log("New Owner:", NEW_OWNER_ADDRESS);

    if (currentOwner !== deployer.address) {
      console.log("❌ Only the current owner can transfer ownership");
      return;
    }

    // Transfer ownership
    console.log("🔄 Transferring ownership...");
    const tx = await pawUSDC.transferOwnership(NEW_OWNER_ADDRESS);
    await tx.wait();
    console.log("✅ Ownership transferred successfully!");

    // Verify the transfer
    const newOwner = await pawUSDC.owner();
    console.log("Verified New Owner:", newOwner);

  } catch (error) {
    console.error("❌ Error transferring ownership:", error);
    throw error;
  }
}

// Function to renounce ownership
async function renounceOwnership() {
  const [deployer] = await ethers.getSigners();
  console.log("Renouncing ownership with account:", deployer.address);

  // Replace with your actual address
  const PAW_USDC_ADDRESS = "0x..."; // Replace with your deployed PawUSDC address

  if (PAW_USDC_ADDRESS === "0x...") {
    console.log("❌ Please replace PAW_USDC_ADDRESS with actual address");
    return;
  }

  try {
    const PawUSDC = await ethers.getContractFactory("PawUSDC");
    const pawUSDC = PawUSDC.attach(PAW_USDC_ADDRESS);

    // Check current owner
    const currentOwner = await pawUSDC.owner();
    console.log("Current Owner:", currentOwner);

    if (currentOwner !== deployer.address) {
      console.log("❌ Only the current owner can renounce ownership");
      return;
    }

    // Confirm renunciation
    console.log("⚠️  WARNING: This will permanently renounce ownership!");
    console.log("⚠️  No one will be able to call owner-only functions after this!");
    
    // Uncomment the lines below to actually renounce ownership
    /*
    console.log("🔄 Renouncing ownership...");
    const tx = await pawUSDC.renounceOwnership();
    await tx.wait();
    console.log("✅ Ownership renounced successfully!");

    // Verify the renunciation
    const newOwner = await pawUSDC.owner();
    console.log("Verified New Owner (should be address(0)):", newOwner);
    */

  } catch (error) {
    console.error("❌ Error renouncing ownership:", error);
    throw error;
  }
}

// Export functions for use in other scripts
module.exports = {
  main,
  transferOwnership,
  renounceOwnership
};

// Run the main function if this script is executed directly
if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
} 