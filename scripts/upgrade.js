const { ethers, upgrades } = require("hardhat");

async function main() {
  // Get the current proxy address from your deployment
  const PROXY_ADDRESS = "0x6b37958AC680d668D7D87d356d95F72fB7c1808A"; // Replace with your actual proxy address
  
  console.log("Upgrading USDCVault proxy at:", PROXY_ADDRESS);
  
  // Deploy the new implementation
  const UsdcVaultV2 = await ethers.getContractFactory("USDCVault");
  
  // Upgrade the proxy
  const upgraded = await upgrades.upgradeProxy(PROXY_ADDRESS, UsdcVaultV2);
  
  console.log("✅ USDCVault upgraded successfully!");
  console.log("New implementation deployed at:", await upgrades.erc1967.getImplementationAddress(PROXY_ADDRESS));
  console.log("Proxy address remains the same:", PROXY_ADDRESS);

}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Upgrade failed:", error);
    process.exit(1);
  }); 