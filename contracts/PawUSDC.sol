// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract PawUSDC is ERC20Upgradeable, OwnableUpgradeable {
    address public borrowingPool;
    
    function initialize() public initializer {
        __ERC20_init("pawUSDC", "pawUSDC");
        __Ownable_init(msg.sender);
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
    
    function mint(address to, uint256 amount) external onlyPool {
        _mint(to, amount);
    }
    
    function burn(address from, uint256 amount) external onlyPool {
        _burn(from, amount);
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
//    protocolFeeRate: 100
//    vaultFeeRate: 200
//    lenderShare: 8000
//    slippageBPS: 100
//    lpToken: "YOUR_LP_TOKEN_ADDRESS"
//    octoRouter: "YOUR_OCTO_ROUTER_ADDRESS"
//    bubbleRouter: "YOUR_BUBBLE_ROUTER_ADDRESS"
//    liquidationVaultShare: 4000
//    liquidationProtocolShare: 2000
//    liquidationLenderShare: 4000