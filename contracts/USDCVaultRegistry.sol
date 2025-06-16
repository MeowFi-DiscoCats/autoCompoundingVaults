// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./USDCVaultFactory.sol";

contract USDCVaultRegistry is Ownable(msg.sender) {
    USDCVaultFactory public factory;
    address public usdc;
    address public priceFetcher;
    address public pawUSDC;

    mapping(string => address) public vaultsByName;
    mapping(address => bool) public isRegisteredVault;
    address[] public registeredVaults;

    event VaultRegistered(address indexed vault, string name);
    event VaultUnregistered(address indexed vault, string name);
    event FactoryUpdated(
        address indexed oldFactory,
        address indexed newFactory
    );
    event CoreAddressesUpdated(
        address indexed usdc,
        address indexed priceFetcher,
        address indexed pawUSDC
    );

    constructor(
        address _factory,
        address _usdc,
        address _priceFetcher,
        address _pawUSDC
    ) {
        require(_factory != address(0), "Invalid factory");
        require(_usdc != address(0), "Invalid USDC");
        require(_priceFetcher != address(0), "Invalid price fetcher");
        require(_pawUSDC != address(0), "Invalid PawUSDC");

        factory = USDCVaultFactory(_factory);
        usdc = _usdc;
        priceFetcher = _priceFetcher;
        pawUSDC = _pawUSDC;
    }

    function createVault(
        string memory name,
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
        address bubbleVault,
        address tokenA,
        address tokenB,
        address lpToken,
        address octoRouter,
        address bubbleRouter
    ) external onlyOwner returns (address) {
        require(vaultsByName[name] == address(0), "Vault name already exists");

        address vault = factory.createVault(
            name,
            usdc,
            priceFetcher,
            pawUSDC,
            bubbleVault,
            tokenA,
            tokenB,
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
            bubbleRouter
        );

        vaultsByName[name] = vault;
        isRegisteredVault[vault] = true;
        registeredVaults.push(vault);

        emit VaultRegistered(vault, name);
        return vault;
    }

    function registerExistingVault(address vault, string memory name)
        external
        onlyOwner
    {
        require(vault != address(0), "Invalid vault");
        require(vaultsByName[name] == address(0), "Vault name already exists");
        require(factory.isVault(vault), "Not a valid vault");
        require(!isRegisteredVault[vault], "Vault already registered");

        vaultsByName[name] = vault;
        isRegisteredVault[vault] = true;
        registeredVaults.push(vault);

        emit VaultRegistered(vault, name);
    }

    function unregisterVault(string memory name) external onlyOwner {
        address vault = vaultsByName[name];
        require(vault != address(0), "Vault not found");

        delete vaultsByName[name];
        isRegisteredVault[vault] = false;

        // Remove from registeredVaults array
        for (uint256 i = 0; i < registeredVaults.length; i++) {
            if (registeredVaults[i] == vault) {
                registeredVaults[i] = registeredVaults[
                    registeredVaults.length - 1
                ];
                registeredVaults.pop();
                break;
            }
        }

        emit VaultUnregistered(vault, name);
    }

    function updateFactory(address _factory) external onlyOwner {
        require(_factory != address(0), "Invalid factory");
        address oldFactory = address(factory);
        factory = USDCVaultFactory(_factory);
        emit FactoryUpdated(oldFactory, _factory);
    }

    function updateCoreAddresses(
        address _usdc,
        address _priceFetcher,
        address _pawUSDC
    ) external onlyOwner {
        require(_usdc != address(0), "Invalid USDC");
        require(_priceFetcher != address(0), "Invalid price fetcher");
        require(_pawUSDC != address(0), "Invalid PawUSDC");

        usdc = _usdc;
        priceFetcher = _priceFetcher;
        pawUSDC = _pawUSDC;

        emit CoreAddressesUpdated(_usdc, _priceFetcher, _pawUSDC);
    }

    function getRegisteredVaults() external view returns (address[] memory) {
        return registeredVaults;
    }

    function getVaultCount() external view returns (uint256) {
        return registeredVaults.length;
    }
}
