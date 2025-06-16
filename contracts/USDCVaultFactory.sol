// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./UsdcVault.sol";

contract USDCVaultFactory is Ownable(msg.sender) {
    using Clones for address;

    address public immutable implementation;
    address[] public vaults;
    mapping(address => bool) public isVault;
    mapping(address => string) public vaultNames;

    event VaultCreated(
        address indexed vault,
        string name,
        uint256 maxLTV,
        uint256 liquidationThreshold,
        uint256 timestamp
    );

    constructor(address _implementation) {
        require(_implementation != address(0), "Invalid implementation");
        implementation = _implementation;
    }

    function createVault(
        string memory name,
        address usdc,
        address priceFetcher,
        address pawUSDC,
        address bubbleVault,
        address tokenA,
        address tokenB,
        uint256 maxLTV,
        uint256 liquidationThreshold,
        uint256 liquidationPenalty,
        uint256 baseRate,
        uint256 multiplier,
        uint256 jumpMultiplier,
        uint256 kink,
        uint256 protocolFeeRate,
        uint256 vaultFeeRate,
        uint256 lenderShare,
        uint256 slippageBPS,
        address lpToken,
        address octoRouter,
        address bubbleRouter,
        uint256 liquidationVaultShare,
        uint256 liquidationProtocolShare,
        uint256 liquidationLenderShare
    ) external onlyOwner returns (address) {
        address clone = implementation.clone();
        USDCVault(clone).initialize(
            usdc,
            priceFetcher,
            pawUSDC,
            bubbleVault,
            tokenA,
            tokenB,
            owner(),
            maxLTV,
            liquidationThreshold,
            liquidationPenalty,
            baseRate,
            multiplier,
            jumpMultiplier,
            kink,
            protocolFeeRate,
            vaultFeeRate,
            lenderShare,
            slippageBPS,
            lpToken,
            octoRouter,
            bubbleRouter,
            liquidationVaultShare,
            liquidationProtocolShare,
            liquidationLenderShare
        );

        vaults.push(clone);
        isVault[clone] = true;
        vaultNames[clone] = name;

        emit VaultCreated(
            clone,
            name,
            maxLTV,
            liquidationThreshold,
            block.timestamp
        );

        return clone;
    }

    function getVaults() external view returns (address[] memory) {
        return vaults;
    }

    function getVaultCount() external view returns (uint256) {
        return vaults.length;
    }

    function getVaultByName(string memory name) external view returns (address) {
        for (uint256 i = 0; i < vaults.length; i++) {
            if (keccak256(bytes(vaultNames[vaults[i]])) == keccak256(bytes(name))) {
                return vaults[i];
            }
        }
        return address(0);
    }
} 