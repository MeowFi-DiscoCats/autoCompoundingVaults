// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IPawUsdc.sol";
import "./interfaces/ICentralizedLendingPool.sol";

contract CentralizedLendingPool is
    ICentralizedLendingPool,
    Ownable,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    struct VaultInfo {
        uint256 borrowedAmount;
        uint256 lastUpdateTime;
        bool isActive;
        uint256 totalInterestPaid; // Track total interest paid by this vault
    }

    struct VaultInterestRate {
        uint256 baseRate;
        uint256 multiplier;
        uint256 jumpMultiplier;
        uint256 kink;
        uint256 lenderShare; // Percentage of interest that goes to lenders
        uint256 vaultFeeRate;
        uint256 protocolFeeRate;
    }

    IERC20 public immutable usdc;
    IPawUSDC public immutable pawUSDC;

    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MIN_DEPOSIT_AMOUNT = 100; // 0.01 USDC
    uint256 public constant MAX_DEPOSIT_AMOUNT = 1000000000; // 1M USDC
    uint256 public constant REDEMPTION_FEE_BPS = 25; // 0.25% redemption fee

    // State variables
    mapping(address => VaultInfo) public vaults;
    mapping(address => VaultInterestRate) public vaultInterestRates;
    address[] public activeVaults;
    mapping(address => uint256) public vaultIndex;

    uint256 public totalDeposits;
    uint256 public totalBorrowed;
    uint256 public lastAccrualTime;

    // Fee configuration
    uint256 public maxUtilizationOnWithdraw;
    address public protocolFeeRecipient;

    // Global interest distributed (for analytics)
    uint256 public totalInterestDistributed;
    uint256 public totalRedemptionFees; // Track total redemption fees collected

    // Events
    event LentUSDC(
        address indexed lender,
        uint256 amount,
        uint256 pawUSDCAmount,
        uint256 timestamp
    );
    event WithdrewUSDC(
        address indexed lender,
        uint256 amount,
        uint256 interest,
        uint256 timestamp
    );
    event VaultBorrowed(
        address indexed vault,
        uint256 amount,
        uint256 timestamp
    );
    event VaultRepaid(address indexed vault, uint256 amount, uint256 timestamp);
    event InterestDistributed(
        address indexed vault,
        uint256 amount,
        uint256 lenderInterest,
        uint256 vaultFee,
        uint256 protocolFee,
        uint256 timestamp
    );
    event RedemptionFeeCollected(
        address indexed lender,
        uint256 withdrawalAmount,
        uint256 redemptionFee,
        uint256 timestamp
    );
    event VaultRegistered(address indexed vault);
    event VaultUnregistered(address indexed vault);
    event VaultInterestRateUpdated(
        address indexed vault,
        uint256 baseRate,
        uint256 multiplier,
        uint256 jumpMultiplier,
        uint256 kink,
        uint256 lenderShare,
        uint256 vaultFeeRate,
        uint256 protocolFeeRate
    );

    constructor(
        address _usdc,
        address _pawUSDC,
        address _owner
    ) Ownable(_owner) {
        require(_usdc != address(0), "Invalid USDC address");
        require(_pawUSDC != address(0), "Invalid PawUSDC address");
        require(_owner != address(0), "Invalid owner address");

        usdc = IERC20(_usdc);
        pawUSDC = IPawUSDC(_pawUSDC);
        lastAccrualTime = block.timestamp;
        maxUtilizationOnWithdraw = 9500; // 95% by default
    }

    // MODIFIERS
    modifier validAmount(uint256 amount) {
        require(amount > 0, "Amount must be greater than 0");
        _;
    }

    modifier onlyRegisteredVault() {
        require(
            vaults[msg.sender].isActive,
            "Only registered vaults can call this"
        );
        _;
    }

    // CORE FUNCTIONS
    function deposit(
        address lender,
        uint256 amount,
        address vault
    ) external override nonReentrant validAmount(amount) {
        require(amount >= MIN_DEPOSIT_AMOUNT, "Amount too small");
        require(amount <= MAX_DEPOSIT_AMOUNT, "Amount too large");
        require(vaults[vault].isActive, "Vault not registered");

        // ✅ FIXED: Transfer USDC directly to PawUSDC contract (like cTokens)
        usdc.safeTransferFrom(lender, address(pawUSDC), amount);
        
        // Mint PawUSDC to lender using the interest-bearing mechanism
        uint256 pawUSDCAmount = pawUSDC.usdcToPawUSDC(amount);
        pawUSDC.mint(lender, amount);
        
        // Update accounting in lending pool (no USDC held here)
        totalDeposits += amount;
        
        emit LentUSDC(lender, amount, pawUSDCAmount, block.timestamp);
    }

  function withdraw(
        address lender,
        uint256 amount,
        address vault
    ) external override nonReentrant {
        require(vaults[vault].isActive, "Vault not registered");

        uint256 pawUSDCBalance = pawUSDC.balanceOf(lender);
        require(pawUSDCBalance > 0, "No PawUSDC to withdraw");

        uint256 maxWithdrawable = pawUSDC.pawUSDCToUSDC(pawUSDCBalance);

        if (amount == 0) {
            amount = maxWithdrawable;
        }

        require(amount <= maxWithdrawable, "Withdraw amount exceeds balance");

        bool isMaxWithdraw = (amount == maxWithdrawable);

        // ✅ FIXED: Calculate PawUSDC to burn based on the actual withdrawal amount
        uint256 pawUSDCToBurn = isMaxWithdraw
            ? pawUSDCBalance
            : pawUSDC.usdcToPawUSDC(amount);

        // ✅ FIXED: Calculate actual USDC withdrawn using the burn amount
        uint256 actualUSDCWithdrawn = pawUSDC.pawUSDCToUSDC(pawUSDCToBurn);

        uint256 redemptionFee = actualUSDCWithdrawn.mulDiv(
            REDEMPTION_FEE_BPS,
            BASIS_POINTS,
            Math.Rounding.Floor
        );
        uint256 netAmountToLender = actualUSDCWithdrawn - redemptionFee;

        // ✅ FIXED: Check PawUSDC contract balance, not lending pool balance
        require(
            usdc.balanceOf(address(pawUSDC)) >= actualUSDCWithdrawn,
            "Insufficient liquidity in PawUSDC"
        );

        // Utilization check
        uint256 newTotalDeposits = totalDeposits > actualUSDCWithdrawn
            ? totalDeposits - actualUSDCWithdrawn
            : 0;

        if (newTotalDeposits > 0 && totalBorrowed > 0) {
            uint256 utilizationAfter = totalBorrowed.mulDiv(
                BASIS_POINTS,
                newTotalDeposits,
                Math.Rounding.Ceil
            );
            require(
                utilizationAfter <= maxUtilizationOnWithdraw,
                "Utilization too high after withdrawal"
            );
        }

        // Update global state
        totalDeposits = newTotalDeposits;
        totalRedemptionFees += redemptionFee;

        // Burn PawUSDC with redemption fee (this will transfer net USDC to lender and fee to protocol)
        pawUSDC.burnWithFee(lender, pawUSDCToBurn, REDEMPTION_FEE_BPS);

        emit WithdrewUSDC(lender, netAmountToLender, redemptionFee, block.timestamp);
        emit RedemptionFeeCollected(
            lender,
            actualUSDCWithdrawn,
            redemptionFee,
            block.timestamp
        );
    }

    function borrow(address vault, uint256 amount)
        external
        override
        onlyRegisteredVault
        nonReentrant
        validAmount(amount)
    {
        // ✅ FIXED: Check PawUSDC contract balance, not lending pool balance
        require(
            usdc.balanceOf(address(pawUSDC)) >= amount,
            "Insufficient liquidity in PawUSDC"
        );

        VaultInfo storage vaultInfo = vaults[vault];
        vaultInfo.borrowedAmount += amount;
        vaultInfo.lastUpdateTime = block.timestamp;
        totalBorrowed += amount;

        // ✅ FIXED: Request PawUSDC to transfer USDC to vault
        pawUSDC.transferUSDCToVault(vault, amount);
        emit VaultBorrowed(vault, amount, block.timestamp);
    }

    function repay(address vault, uint256 amount)
        external
        override
        onlyRegisteredVault
        nonReentrant
        validAmount(amount)
    {
        VaultInfo storage vaultInfo = vaults[vault];
        require(
            vaultInfo.borrowedAmount >= amount,
            "Repay amount exceeds borrowed"
        );

        vaultInfo.borrowedAmount -= amount;
        vaultInfo.lastUpdateTime = block.timestamp;
        totalBorrowed -= amount;

        // ✅ FIXED: Vault handles USDC transfer directly to PawUSDC
        // No need to transfer USDC here since vault does it directly
        emit VaultRepaid(vault, amount, block.timestamp);
    }

    function distributeInterest(uint256 amount)
        external
        override
        onlyRegisteredVault
        nonReentrant
    {
        require(amount > 0, "Amount must be greater than 0");
        require(totalDeposits > 0, "No deposits to distribute to");

        // Get vault-specific interest rate configuration
        VaultInterestRate storage rateConfig = vaultInterestRates[msg.sender];
        require(
            rateConfig.lenderShare > 0,
            "Vault interest rate not configured"
        );

        // ✅ FIXED: Transfer interest from sender to PawUSDC contract
        usdc.safeTransferFrom(msg.sender, address(pawUSDC), amount);

        // This amount is pure lender interest (vault and protocol fees already handled by vault)
        uint256 lenderInterest = amount;

        // Update vault's total interest paid
        vaults[msg.sender].totalInterestPaid += amount;

        // Distribute lender interest through PawUSDC exchange rate mechanism
        if (lenderInterest > 0) {
            pawUSDC.accrueInterest(lenderInterest);
            totalInterestDistributed += lenderInterest;
        }

        emit InterestDistributed(
            msg.sender,
            amount,
            lenderInterest,
            0, // vaultFee (handled by vault)
            0, // protocolFee (handled by vault)
            block.timestamp
        );
    }

    // INTERNAL FUNCTIONS
    function _addActiveVault(address vault) internal {
        if (
            vaultIndex[vault] == 0 &&
            (activeVaults.length == 0 || activeVaults[0] != vault)
        ) {
            activeVaults.push(vault);
            vaultIndex[vault] = activeVaults.length;
        }
    }

    function _removeActiveVault(address vault) internal {
        uint256 index = vaultIndex[vault];
        if (index == 0) return;

        uint256 arrayIndex = index - 1;
        uint256 lastIndex = activeVaults.length - 1;

        if (arrayIndex != lastIndex) {
            address lastVault = activeVaults[lastIndex];
            activeVaults[arrayIndex] = lastVault;
            vaultIndex[lastVault] = index;
        }

        activeVaults.pop();
        delete vaultIndex[vault];
    }

    // ADMIN FUNCTIONS
    function registerVault(
        address vault,
        uint256 baseRate,
        uint256 multiplier,
        uint256 jumpMultiplier,
        uint256 kink,
        uint256 lenderShare,
        uint256 vaultFeeRate,
        uint256 protocolFeeRate
    ) external onlyOwner {
        require(vault != address(0), "Invalid vault address");
        require(!vaults[vault].isActive, "Vault already registered");
        require(lenderShare <= BASIS_POINTS, "Invalid lender share");
        require(vaultFeeRate <= BASIS_POINTS, "Invalid vault fee rate");
        require(protocolFeeRate <= BASIS_POINTS, "Invalid protocol fee rate");
        require(
            lenderShare + vaultFeeRate + protocolFeeRate <= BASIS_POINTS,
            "Total fees exceed 100%"
        );

        vaults[vault] = VaultInfo({
            borrowedAmount: 0,
            lastUpdateTime: block.timestamp,
            isActive: true,
            totalInterestPaid: 0
        });

        vaultInterestRates[vault] = VaultInterestRate({
            baseRate: baseRate,
            multiplier: multiplier,
            jumpMultiplier: jumpMultiplier,
            kink: kink,
            lenderShare: lenderShare,
            vaultFeeRate: vaultFeeRate,
            protocolFeeRate: protocolFeeRate
        });

        _addActiveVault(vault);
        emit VaultRegistered(vault);
    }

    function unregisterVault(address vault) external onlyOwner {
        require(vaults[vault].isActive, "Vault not registered");
        require(
            vaults[vault].borrowedAmount == 0,
            "Vault has outstanding debt"
        );

        vaults[vault].isActive = false;
        delete vaultInterestRates[vault];
        _removeActiveVault(vault);

        emit VaultUnregistered(vault);
    }

    function updateVaultInterestRate(
        address vault,
        uint256 baseRate,
        uint256 multiplier,
        uint256 jumpMultiplier,
        uint256 kink,
        uint256 lenderShare,
        uint256 vaultFeeRate,
        uint256 protocolFeeRate
    ) external onlyOwner {
        require(vaults[vault].isActive, "Vault not registered");
        require(lenderShare <= BASIS_POINTS, "Invalid lender share");
        require(vaultFeeRate <= BASIS_POINTS, "Invalid vault fee rate");
        require(protocolFeeRate <= BASIS_POINTS, "Invalid protocol fee rate");
        require(
            lenderShare + vaultFeeRate + protocolFeeRate <= BASIS_POINTS,
            "Total fees exceed 100%"
        );

        VaultInterestRate storage rateConfig = vaultInterestRates[vault];
        rateConfig.baseRate = baseRate;
        rateConfig.multiplier = multiplier;
        rateConfig.jumpMultiplier = jumpMultiplier;
        rateConfig.kink = kink;
        rateConfig.lenderShare = lenderShare;
        rateConfig.vaultFeeRate = vaultFeeRate;
        rateConfig.protocolFeeRate = protocolFeeRate;

        emit VaultInterestRateUpdated(
            vault,
            baseRate,
            multiplier,
            jumpMultiplier,
            kink,
            lenderShare,
            vaultFeeRate,
            protocolFeeRate
        );
    }

    function setMaxUtilizationOnWithdraw(uint256 bps) external onlyOwner {
        require(bps <= BASIS_POINTS, "Utilization rate too high");
        require(bps >= 5000, "Utilization rate too low"); // Minimum 50%
        maxUtilizationOnWithdraw = bps;
    }

    function setProtocolFeeRecipient(address recipient) external onlyOwner {
        protocolFeeRecipient = recipient;
    }

    function approvePawUSDC(uint256 amount) external onlyOwner {
        usdc.approve(address(pawUSDC), amount);
    }

    // VIEW FUNCTIONS
    function getTotalDeposits() external view override returns (uint256) {
        return totalDeposits;
    }

    function getAvailableLiquidity() external view override returns (uint256) {
        // ✅ FIXED: Return available liquidity from PawUSDC contract
        return usdc.balanceOf(address(pawUSDC));
    }

    function getTotalBorrowed() external view override returns (uint256) {
        return totalBorrowed;
    }

    function getVaultBorrowed(address vault)
        external
        view
        override
        returns (uint256)
    {
        return vaults[vault].borrowedAmount;
    }

    function getUtilizationRate() external view returns (uint256) {
        if (totalDeposits == 0) return 0;
        return
            totalBorrowed.mulDiv(
                BASIS_POINTS,
                totalDeposits,
                Math.Rounding.Floor
            );
    }

    function getVaultInterestRate(address vault)
        external
        view
        returns (
            uint256 baseRate,
            uint256 multiplier,
            uint256 jumpMultiplier,
            uint256 kink,
            uint256 lenderShare,
            uint256 vaultFeeRate,
            uint256 protocolFeeRate
        )
    {
        VaultInterestRate storage rateConfig = vaultInterestRates[vault];
        return (
            rateConfig.baseRate,
            rateConfig.multiplier,
            rateConfig.jumpMultiplier,
            rateConfig.kink,
            rateConfig.lenderShare,
            rateConfig.vaultFeeRate,
            rateConfig.protocolFeeRate
        );
    }

    function getActiveVaults() external view returns (address[] memory) {
        return activeVaults;
    }

    function getVaultCount() external view returns (uint256) {
        return activeVaults.length;
    }

    // Get current PawUSDC exchange rate
    function getPawUSDCExchangeRate() external view returns (uint256) {
        return pawUSDC.getExchangeRate();
    }

    // Get total underlying USDC in PawUSDC
    function getPawUSDCTotalUnderlying() external view returns (uint256) {
        return pawUSDC.getTotalUnderlying();
    }

    function getVaultTotalInterestPaid(address vault)
        external
        view
        returns (uint256)
    {
        return vaults[vault].totalInterestPaid;
    }

    // Get total redemption fees collected over lifetime
    function getTotalRedemptionFees() external view returns (uint256) {
        return totalRedemptionFees;
    }

    function getTotalInterestDistributed() external view returns (uint256) {
        return totalInterestDistributed;
    }
}
