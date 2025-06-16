// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./vaultV1uups.sol";
import "./bubbleFiABI.sol";
import "./uniswaphelper.sol";
import "./interfaces/IMonadPriceFetcher.sol";
import "./PawUSDC.sol";

contract USDCBorrowingPoolV2 is
    Initializable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using Math for uint256;

    struct VaultConfig {
        uint256 maxLTV;
        uint256 liquidationThreshold;
        uint256 liquidationPenalty;
        uint256 baseRate;
        uint256 multiplier;
        uint256 jumpMultiplier;
        uint256 kink;
        bool borrowingEnabled;
        bool active;
        uint256 totalLent;
        uint256 totalBorrowed;
        uint256 totalCollateral;
        uint256 protocolFeeRate;
        uint256 vaultFeeRate;
        uint256 lenderShare;
        uint256 slippageBPS;
        uint256 minBorrowAmount;
        uint256 minLiquidationAmount;
    }

    struct LenderInfo {
        uint256 depositAmount;
        uint256 lastUpdateTime;
        uint256 accruedInterest;
        uint256 pawUSDCAmount;
        uint256 interestIndex;
    }

    struct BorrowerPosition {
        uint256 collateralAmount;
        uint256 borrowedAmount;
        uint256 lastUpdateTime;
        uint256 accruedInterest;
        bool isActive;
    }

    PawUSDC public pawUSDC;
    IERC20Upgradeable public usdc;
    IMonadPriceFetcher public priceFetcher;

    address public constant USDC_ADDRESS =
        0xf817257fed379853cDe0fa4F97AB987181B1E5Ea;
    address public constant WMON_ADDRESS =
        0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701;
    address public constant SHMON_ADDRESS =
        0x3a98250F98Dd388C211206983453837C8365BDc1;

    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant USDC_DECIMALS = 6;
    uint256 public constant ORACLE_DECIMALS = 18;
    uint256 public constant CALCULATION_DECIMALS = 18;
    uint256 public constant USDC_TO_CALC_SCALE = 1e12;
    uint256 public constant KINK_UTILIZATION = 8000; // 80% in basis points
    uint256 public constant DEFAULT_LTV = 7000; // 70% in basis points
    uint256 public constant LIQUIDATION_LTV = 7100; // 71% in basis points
    uint256 public constant DEFAULT_BASE_RATE = 1000;

    uint256 public constant MIN_DEPOSIT_AMOUNT = 100; // 0.01 USDC
    uint256 public constant MAX_DEPOSIT_AMOUNT = 1000000000; // 1M USDC

    // State variables
    mapping(address => VaultConfig) public vaultConfigs;
    mapping(address => mapping(address => LenderInfo)) public vaultLenders;
    mapping(address => mapping(address => BorrowerPosition)) public borrowers;
    mapping(address => address[]) public vaultActiveBorrowers;
    mapping(address => mapping(address => uint256)) public vaultBorrowerIndex;
    mapping(address => BubbleLPVault) public vaults;
    mapping(address => uint256) public vaultHardcodedYield; //  hardcoded yield per vault
    mapping(address => address[]) public vaultActiveLenders;
    mapping(address => mapping(address => uint256)) public vaultLenderIndex;
    mapping(address => uint256) public vaultAPY;

    BubbleLPVault public bubbleVault;
    IERC20Upgradeable public tokenA;
    IERC20Upgradeable public tokenB;
    IERC20Upgradeable public lpToken;
    IOctoswapRouter02 public octoRouter;
    IBubbleV1Router public bubbleRouter;

    uint256 public lastAccrualTime;
    uint256 public counter;

    uint256 public accumulatedFees;
    bool public liquidationEnabled;
    bool public borrowingPaused;
    bool public liquidationsPaused;

    // Fee recipient addresses and borrow caps
    address public protocolFeeRecipient;
    mapping(address => address) public vaultFeeRecipient;
    uint256 public globalMaxBorrow;
    mapping(address => uint256) public vaultMaxBorrow;
    // Accrued fees
    mapping(address => uint256) public accruedVaultFees; // per vault
    mapping(address => uint256) public accruedProtocolFees; // per vault
    // Withdrawal control
    uint256 public maxUtilizationOnWithdraw = 9500; // 95% by default

    // Add new state variables for interest tracking
    mapping(address => uint256) public vaultInterestIndex; // Tracks global interest index per vault
    mapping(address => mapping(address => uint256)) public lenderInterestIndex; // Tracks lender's last interest index

    // Add new state variable to track active vaults
    address[] public activeVaults;
    mapping(address => bool) public isActiveVault;

    // Add emergency pause functionality
    bool public emergencyMode;

    // Events
    event LentUSDC(
        address indexed vault,
        address indexed lender,
        uint256 amount,
        uint256 pawUSDCAmount,
        uint256 timestamp
    );
    event WithdrewUSDC(
        address indexed vault,
        address indexed lender,
        uint256 amount,
        uint256 interest,
        uint256 timestamp
    );
    event Borrowed(
        address indexed vault,
        address indexed borrower,
        uint256 collateral,
        uint256 borrowAmount,
        uint256 timestamp
    );
    event Repaid(
        address indexed vault,
        address indexed borrower,
        uint256 repayAmount,
        uint256 interest,
        uint256 timestamp
    );
    event Liquidated(
        address indexed vault,
        address indexed borrower,
        address indexed liquidator,
        uint256 collateralLiquidated,
        uint256 debtRepaid,
        uint256 penalty,
        uint256 timestamp
    );
    event CollateralReturned(
        address indexed vault,
        address indexed borrower,
        uint256 collateralAmount,
        uint256 timestamp
    );
    event VaultAdded(
        address indexed vault,
        uint256 maxLTV,
        uint256 liquidationThreshold
    );
    event VaultRemoved(address indexed vault);
    event InterestRateModelUpdated(
        address indexed vault,
        uint256 baseRate,
        uint256 multiplier,
        uint256 jumpMultiplier,
        uint256 kink
    );
    event TokensRecovered(
        address indexed token,
        address indexed to,
        uint256 amount
    );
    event CollateralDeposited(
        address indexed vault,
        address indexed borrower,
        uint256 amount,
        uint256 timestamp
    );

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _usdc,
        address _priceFetcher,
        address _pawUSDC,
        address _owner,
        address _bubbleVault,
        address _tokenA,
        address _tokenB,
        address _lpToken,
        IOctoswapRouter02 _octoRouter
    ) public initializer {
        require(_usdc != address(0), "Invalid USDC");
        require(_priceFetcher != address(0), "Invalid price fetcher");
        require(_pawUSDC != address(0), "Invalid PawUSDC");
        require(_owner != address(0), "Invalid owner");
        require(_bubbleVault != address(0), "Invalid bubble vault");
        require(_tokenA != address(0), "Invalid token A");
        require(_tokenB != address(0), "Invalid token B");
        require(_lpToken != address(0), "Invalid LP token");
        require(address(_octoRouter) != address(0), "Invalid octo router");

        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        usdc = IERC20Upgradeable(_usdc);
        priceFetcher = IMonadPriceFetcher(_priceFetcher);
        pawUSDC = PawUSDC(_pawUSDC);
        bubbleVault = BubbleLPVault(_bubbleVault);
        tokenA = IERC20Upgradeable(_tokenA);
        tokenB = IERC20Upgradeable(_tokenB);
        lpToken = IERC20Upgradeable(_lpToken);
        octoRouter = IOctoswapRouter02(_octoRouter);
        lastAccrualTime = block.timestamp;
        counter = 0;
    }

    function addVault(
        address vault,
        uint256 maxLTV_,
        uint256 liquidationThreshold_,
        uint256 liquidationPenalty_,
        uint256 baseRate_,
        uint256 multiplier_,
        uint256 jumpMultiplier_,
        uint256 kink_,
        uint256 protocolFeeRate_,
        uint256 lenderShare_,
        uint256 slippageBPS_
    ) external onlyOwner {
        require(vault != address(0), "Invalid vault address");
        require(!vaultConfigs[vault].active, "Vault already exists");
        require(maxLTV_ <= liquidationThreshold_, "Invalid LTV");
        require(kink_ <= BASIS_POINTS, "Invalid kink");
        require(protocolFeeRate_ <= BASIS_POINTS, "Invalid protocol fee rate");
        require(lenderShare_ <= BASIS_POINTS, "Invalid lender share");
        require(slippageBPS_ <= BASIS_POINTS, "Invalid slippage");

        VaultConfig storage config = vaultConfigs[vault];
        config.maxLTV = maxLTV_;
        config.liquidationThreshold = liquidationThreshold_;
        config.liquidationPenalty = liquidationPenalty_;
        config.baseRate = baseRate_;
        config.multiplier = multiplier_;
        config.jumpMultiplier = jumpMultiplier_;
        config.kink = kink_;
        config.protocolFeeRate = protocolFeeRate_;
        config.lenderShare = lenderShare_;
        config.slippageBPS = slippageBPS_;
        config.borrowingEnabled = true;
        config.active = true;

        vaults[vault] = BubbleLPVault(vault);
        
        // Add to active vaults
        if (!isActiveVault[vault]) {
            activeVaults.push(vault);
            isActiveVault[vault] = true;
        }

        emit VaultAdded(vault, maxLTV_, liquidationThreshold_);
    }

    function _addActiveBorrower(address vault, address borrower) internal {
        if (
            vaultBorrowerIndex[vault][borrower] == 0 &&
            (vaultActiveBorrowers[vault].length == 0 ||
                vaultActiveBorrowers[vault][0] != borrower)
        ) {
            vaultActiveBorrowers[vault].push(borrower);
            vaultBorrowerIndex[vault][borrower] = vaultActiveBorrowers[vault]
                .length;
        }
    }

    function _removeActiveBorrower(address vault, address borrower) internal {
        uint256 index = vaultBorrowerIndex[vault][borrower];
        if (index == 0) return;

        uint256 arrayIndex = index - 1;
        uint256 lastIndex = vaultActiveBorrowers[vault].length - 1;

        if (arrayIndex != lastIndex) {
            address lastBorrower = vaultActiveBorrowers[vault][lastIndex];
            vaultActiveBorrowers[vault][arrayIndex] = lastBorrower;
            vaultBorrowerIndex[vault][lastBorrower] = index;
        }

        vaultActiveBorrowers[vault].pop();
        delete vaultBorrowerIndex[vault][borrower];
    }

    function getLiquidatablePositions(address vault, uint256 maxPositions)
        public
        view
        returns (address[] memory liquidatable)
    {
        if (!liquidationEnabled || vaultActiveBorrowers[vault].length == 0) {
            return new address[](0);
        }

        address[] memory temp = new address[](maxPositions);
        uint256 count = 0;

        for (
            uint256 i = 0;
            i < vaultActiveBorrowers[vault].length && count < maxPositions;
            i++
        ) {
            address borrower = vaultActiveBorrowers[vault][i];
            BorrowerPosition storage position = borrowers[vault][borrower];

            if (position.isActive && !_isHealthy(vault, borrower, true)) {
                temp[count] = borrower;
                count++;
            }
        }

        liquidatable = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            liquidatable[i] = temp[i];
        }
    }

    function getFirstLiquidatablePosition(address vault)
        public
        view
        returns (address borrower)
    {
        if (!liquidationEnabled || vaultActiveBorrowers[vault].length == 0) {
            return address(0);
        }

        for (uint256 i = 0; i < vaultActiveBorrowers[vault].length; i++) {
            address currentBorrower = vaultActiveBorrowers[vault][i];
            BorrowerPosition storage position = borrowers[vault][
                currentBorrower
            ];

            if (
                position.isActive && !_isHealthy(vault, currentBorrower, true)
            ) {
                return currentBorrower;
            }
        }

        return address(0);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}

    function version() external pure returns (string memory) {
        return "1.0.0";
    }

    // MODIFIERS

    modifier validAmount(uint256 amount) {
        require(amount > 0, "Amount must be greater than 0");
        _;
    }

    modifier onlyActiveBorrower(address vault, address borrower) {
        require(borrowers[vault][borrower].isActive, "No active position");
        _;
    }

    modifier notBorrowingPaused() {
        require(!borrowingPaused, "Borrowing is paused");
        _;
    }

    modifier notLiquidationsPaused() {
        require(!liquidationsPaused, "Liquidations are paused");
        _;
    }

    modifier notInEmergencyMode() {
        require(!emergencyMode, "Contract is in emergency mode");
        _;
    }

    function setLiquidationEnabled(bool _enabled) external onlyOwner {
        liquidationEnabled = _enabled;
    }

    /// Get current utilization rate
    function getUtilizationRate(address vault) public view returns (uint256) {
        VaultConfig storage config = vaultConfigs[vault];
        if (config.totalLent == 0) return 0;
        return
            config.totalBorrowed.mulDiv(
                BASIS_POINTS,
                config.totalLent,
                Math.Rounding.Floor
            );
    }

    /// Calculate current borrow rate based on utilization
    function getBorrowRate(address vault) public view returns (uint256) {
        require(vaultConfigs[vault].active, "Vault not active");
        uint256 utilization = getUtilizationRate(vault);
        uint256 yieldGenerated = vaultHardcodedYield[vault] > 0
            ? vaultHardcodedYield[vault]
            : DEFAULT_BASE_RATE;

        uint256 baseBorrowRate = yieldGenerated / 3;

        if (utilization <= KINK_UTILIZATION) {
            // Before kink: Use yield method - scale base rate by utilization
            return
                baseBorrowRate.mulDiv(
                    utilization,
                    BASIS_POINTS,
                    Math.Rounding.Floor
                );
        } else {
            // After kink (>80%): Use kink method - base rate + jump rate
            VaultConfig storage config = vaultConfigs[vault];

            // Calculate base rate at kink point
            uint256 baseRateAtKink = baseBorrowRate.mulDiv(
                KINK_UTILIZATION,
                BASIS_POINTS,
                Math.Rounding.Floor
            );

            // Calculate jump rate for utilization above kink
            uint256 excessUtilization = utilization - KINK_UTILIZATION;
            uint256 jumpRate = excessUtilization.mulDiv(
                config.jumpMultiplier,
                BASIS_POINTS,
                Math.Rounding.Floor
            );

            return baseRateAtKink + jumpRate;
        }
    }

    /// Calculate supply rate (what lenders earn)
    function getSupplyRate(address vault) public view returns (uint256) {
        uint256 utilization = getUtilizationRate(vault);
        uint256 borrowRate = getBorrowRate(vault);

        // Supply Rate = Borrow Rate * Utilization * (1 - Reserve Factor)
        uint256 rateToPool = borrowRate.mulDiv(
            vaultConfigs[vault].lenderShare,
            BASIS_POINTS,
            Math.Rounding.Floor
        );
        return
            utilization.mulDiv(rateToPool, BASIS_POINTS, Math.Rounding.Floor);
    }

    /// Convert USDC (6 decimals) to calculation format (18 decimals)
    function _toCalculationDecimals(uint256 usdcAmount)
        private
        pure
        returns (uint256)
    {
        return usdcAmount * USDC_TO_CALC_SCALE;
    }

    /// Convert calculation format (18 decimals) to USDC (6 decimals)
    function _fromCalculationDecimals(uint256 calcAmount)
        private
        pure
        returns (uint256)
    {
        return calcAmount / USDC_TO_CALC_SCALE;
    }

    /// Get token price in USDC using oracle
    /// @return price Price in calculation decimals (18 decimals) representing USDC value per token
    function _getTokenPriceInUSDC(address token)
        internal
        view
        returns (uint256 price)
    {
        if (token == USDC_ADDRESS) {
            return 1e18; // 1 USDC = 1e18 in calculation format
        }

        if (token == WMON_ADDRESS) {
            uint256 wmonPriceInUSDC = priceFetcher.getPrice(
                WMON_ADDRESS,
                USDC_ADDRESS
            );
            require(wmonPriceInUSDC > 0, "Invalid WMON price");
            return wmonPriceInUSDC; // Already in 18 decimals
        }

        if (token == SHMON_ADDRESS) {
            try priceFetcher.getPrice(SHMON_ADDRESS, USDC_ADDRESS) returns (
                uint256 directPrice
            ) {
                if (directPrice > 0) {
                    return directPrice; // Already in 18 decimals
                }
            } catch {
                //  SHMON -> WMON -> USDC
                uint256 shmonPerWmon = priceFetcher.getPriceInWmonad(
                    SHMON_ADDRESS
                );
                uint256 wmonPriceInUSDC = priceFetcher.getPrice(
                    WMON_ADDRESS,
                    USDC_ADDRESS
                );

                require(
                    shmonPerWmon > 0 && wmonPriceInUSDC > 0,
                    "Invalid SHMON price data"
                );

                return
                    shmonPerWmon.mulDiv(
                        wmonPriceInUSDC,
                        1e18,
                        Math.Rounding.Floor
                    );
            }
        }

        // Generic token
        try priceFetcher.getPrice(token, USDC_ADDRESS) returns (
            uint256 directPrice
        ) {
            if (directPrice > 0) {
                return directPrice; // Already in 18 decimals
            }
        } catch {
            uint256 tokenPerWmon = priceFetcher.getPriceInWmonad(token);
            uint256 wmonPriceInUSDC = priceFetcher.getPrice(
                WMON_ADDRESS,
                USDC_ADDRESS
            );

            require(
                tokenPerWmon > 0 && wmonPriceInUSDC > 0,
                "No price route available"
            );

            return
                tokenPerWmon.mulDiv(wmonPriceInUSDC, 1e18, Math.Rounding.Floor);
        }
    }

    /// Get collateral value in USDC
    /// @param vaultShares Amount of vault shares
    /// @return value Total value in USDC (6 decimals)
    function _getCollateralValue(uint256 vaultShares)
        internal
        view
        returns (uint256 value)
    {
        if (vaultShares == 0) return 0;

        // Get LP tokens for vault shares
        uint256 lpTokenAmount = bubbleVault.previewRedeem(vaultShares);
        require(lpTokenAmount > 0, "Invalid vault shares");

        // Calculate underlying token amounts
        (
            uint256 tokenAAmount,
            uint256 tokenBAmount
        ) = _calculateTokenAmountsFromLP(lpTokenAmount);

        // Get token prices in USDC
        uint256 priceA = _getTokenPriceInUSDC(address(tokenA)); // 18 decimals
        uint256 priceB = _getTokenPriceInUSDC(address(tokenB)); // 18 decimals

        // Calculate values
        uint256 valueA = tokenAAmount.mulDiv(priceA, 1e18, Math.Rounding.Floor);
        uint256 valueB = tokenBAmount.mulDiv(priceB, 1e18, Math.Rounding.Floor);

        uint256 totalValueCalc = valueA + valueB; // 18 decimals

        // Convert to USDC decimals (6 decimals)
        return _fromCalculationDecimals(totalValueCalc);
    }

    /// Calculate token amounts from LP tokens
    function _calculateTokenAmountsFromLP(uint256 lpTokenAmount)
        internal
        view
        returns (uint256 tokenAAmount, uint256 tokenBAmount)
    {
        if (lpTokenAmount == 0) return (0, 0);

        uint256 totalSupply = lpToken.totalSupply();
        require(totalSupply > 0, "LP token has no supply");

        uint256 reserveA = tokenA.balanceOf(address(lpToken));
        uint256 reserveB = tokenB.balanceOf(address(lpToken));

        tokenAAmount = lpTokenAmount.mulDiv(
            reserveA,
            totalSupply,
            Math.Rounding.Floor
        );
        tokenBAmount = lpTokenAmount.mulDiv(
            reserveB,
            totalSupply,
            Math.Rounding.Floor
        );
    }

    ///  Lend USDC to the pool
    /// @param amount Amount (6 decimals) of USDC to lend
    function lendUSDC(address vault, uint256 amount)
        external
        nonReentrant
        validAmount(amount)
        notInEmergencyMode
    {
        require(amount >= MIN_DEPOSIT_AMOUNT, "Amount too small");
        require(amount <= MAX_DEPOSIT_AMOUNT, "Amount too large");
        require(vaultConfigs[vault].active, "Vault not active");

        _accrueInterest(vault);

        LenderInfo storage lender = vaultLenders[vault][msg.sender];
        if (lender.depositAmount > 0) {
            _updateLenderInterest(vault, msg.sender);
        }

        lender.depositAmount += amount;
        lender.lastUpdateTime = block.timestamp;
        lenderInterestIndex[vault][msg.sender] = vaultInterestIndex[vault];
        vaultConfigs[vault].totalLent += amount;

        _addActiveLender(vault, msg.sender);

        usdc.safeTransferFrom(msg.sender, address(this), amount);

        // Mint PawUSDC to lender
        pawUSDC.mint(msg.sender, amount);
        lender.pawUSDCAmount += amount;

        emit LentUSDC(vault, msg.sender, amount, amount, block.timestamp);
    }

    ///  Withdraw lent USDC plus earned interest
    /// @param amount Amount to withdraw (0 = withdraw all)
    function withdrawUSDC(address vault, uint256 amount) external nonReentrant notInEmergencyMode {
        LenderInfo storage lender = vaultLenders[vault][msg.sender];
        require(lender.depositAmount > 0, "No deposit found");
        require(amount > 0, "Amount must be greater than 0");

        _accrueInterest(vault);
        _updateLenderInterest(vault, msg.sender);

        if (amount == 0) {
            amount = lender.depositAmount;
        }
        require(amount <= lender.depositAmount, "Insufficient deposit");

        // Calculate interest to withdraw proportionally
        uint256 interestToWithdraw = lender.accruedInterest.mulDiv(
            amount,
            lender.depositAmount,
            Math.Rounding.Floor
        );

        uint256 totalWithdraw = amount + interestToWithdraw;
        require(
            usdc.balanceOf(address(this)) >= totalWithdraw,
            "Insufficient liquidity"
        );

        // Withdrawal control: check utilization after withdrawal
        uint256 newTotalLent = vaultConfigs[vault].totalLent - amount;
        uint256 utilizationAfter = newTotalLent == 0
            ? 0
            : vaultConfigs[vault].totalBorrowed.mulDiv(
                BASIS_POINTS,
                newTotalLent,
                Math.Rounding.Floor
            );
        require(
            utilizationAfter <= maxUtilizationOnWithdraw,
            "Utilization too high after withdrawal"
        );

        // Update lender state
        lender.depositAmount -= amount;
        lender.accruedInterest -= interestToWithdraw;
        lender.lastUpdateTime = block.timestamp;
        lenderInterestIndex[vault][msg.sender] = vaultInterestIndex[vault];

        // Update vault state
        vaultConfigs[vault].totalLent -= amount;

        // Remove from active lenders if fully withdrawn
        if (lender.depositAmount == 0) {
            _removeActiveLender(vault, msg.sender);
        }

        // Burn PawUSDC tokens
        pawUSDC.burn(msg.sender, amount);
        lender.pawUSDCAmount -= amount;

        usdc.safeTransfer(msg.sender, totalWithdraw);
        emit WithdrewUSDC(
            vault,
            msg.sender,
            amount,
            interestToWithdraw,
            block.timestamp
        );
    }

    // Add this new function for depositing additional collateral
    function depositCollateral(address vault, uint256 collateralAmount)
        external
        nonReentrant
        onlyActiveBorrower(vault, msg.sender)
        validAmount(collateralAmount)
    {
        require(
            IERC20Upgradeable(address(bubbleVault)).balanceOf(msg.sender) >=
                collateralAmount,
            "Insufficient vault shares balance"
        );

        _accrueInterest(vault);
        _updateBorrowerInterest(vault, msg.sender);

        BorrowerPosition storage position = borrowers[vault][msg.sender];

        IERC20Upgradeable(address(bubbleVault)).safeTransferFrom(
            msg.sender,
            address(this),
            collateralAmount
        );

        position.collateralAmount += collateralAmount;
        position.lastUpdateTime = block.timestamp;

        vaultConfigs[vault].totalCollateral += collateralAmount;

        emit CollateralDeposited(
            vault,
            msg.sender,
            collateralAmount,
            block.timestamp
        );
    }

    function borrow(
        address vault,
        uint256 collateralAmount,
        uint256 borrowAmount
    ) external nonReentrant notBorrowingPaused validAmount(borrowAmount) notInEmergencyMode {
        require(vaultConfigs[vault].active, "Vault not active");
        require(vaultConfigs[vault].borrowingEnabled, "Borrowing disabled");
        require(
            usdc.balanceOf(address(this)) >= borrowAmount,
            "Insufficient liquidity"
        );

        _accrueInterest(vault);

        // Enforce max borrow caps
        uint256 newVaultTotalBorrowed = vaultConfigs[vault].totalBorrowed +
            borrowAmount;
        require(
            vaultMaxBorrow[vault] == 0 ||
                newVaultTotalBorrowed <= vaultMaxBorrow[vault],
            "Exceeds vault max borrow cap"
        );
        require(
            globalMaxBorrow == 0 ||
                (getTotalBorrowedAllVaults() + borrowAmount) <= globalMaxBorrow,
            "Exceeds global max borrow cap"
        );

        BorrowerPosition storage position = borrowers[vault][msg.sender];

        if (collateralAmount > 0) {
            require(
                IERC20Upgradeable(address(bubbleVault)).balanceOf(msg.sender) >=
                    collateralAmount,
                "Insufficient vault shares balance"
            );

            IERC20Upgradeable(address(bubbleVault)).safeTransferFrom(
                msg.sender,
                address(this),
                collateralAmount
            );
        }

        uint256 totalBorrowAmount = borrowAmount;
        uint256 totalCollateralAmount = collateralAmount;

        if (position.isActive) {
            _updateBorrowerInterest(vault, msg.sender);

            // Add existing debt and collateral
            uint256 existingDebt = position.borrowedAmount +
                position.accruedInterest;
            totalBorrowAmount += existingDebt;
            totalCollateralAmount += position.collateralAmount;
        } else {
            require(collateralAmount > 0, "New position requires collateral");
        }

        // Calculate total collateral value with all collateral
        uint256 totalCollateralValueUSDC = _getCollateralValue(
            totalCollateralAmount
        );
        require(totalCollateralValueUSDC > 0, "Invalid collateral value");

        uint256 maxBorrowAmount = totalCollateralValueUSDC.mulDiv(
            vaultConfigs[vault].maxLTV,
            BASIS_POINTS,
            Math.Rounding.Floor
        );
        require(totalBorrowAmount <= maxBorrowAmount, "Exceeds maximum LTV");

        // Update position
        if (position.isActive) {
            position.collateralAmount += collateralAmount;
            position.borrowedAmount += borrowAmount;
        } else {
            position.collateralAmount = collateralAmount;
            position.borrowedAmount = borrowAmount;
            position.isActive = true;
            _addActiveBorrower(vault, msg.sender);
        }
        position.lastUpdateTime = block.timestamp;

        require(
            _isHealthy(vault, msg.sender, false),
            "Position unhealthy after borrow"
        );

        // Update pool state
        vaultConfigs[vault].totalCollateral += collateralAmount;
        vaultConfigs[vault].totalBorrowed += borrowAmount;

        usdc.safeTransfer(msg.sender, borrowAmount);
        emit Borrowed(
            vault,
            msg.sender,
            collateralAmount,
            borrowAmount,
            block.timestamp
        );
    }

    // Add this view function to check borrowing capacity
    function getBorrowingCapacity(address vault, address borrower)
        external
        view
        returns (
            uint256 maxBorrow,
            uint256 currentDebt,
            uint256 availableToBorrow
        )
    {
        BorrowerPosition storage position = borrowers[vault][borrower];

        if (!position.isActive) {
            return (0, 0, 0);
        }

        uint256 collateralValueUSDC = _getCollateralValue(
            position.collateralAmount
        );
        maxBorrow = collateralValueUSDC.mulDiv(
            vaultConfigs[vault].maxLTV,
            BASIS_POINTS,
            Math.Rounding.Floor
        );
        currentDebt =
            position.borrowedAmount +
            _calculateBorrowerInterest(vault, borrower);
        availableToBorrow = maxBorrow > currentDebt
            ? maxBorrow - currentDebt
            : 0;
    }

    ///  Repay borrowed USDC
    /// @param repayAmount Amount to repay
    function repay(address vault, uint256 repayAmount)
        external
        nonReentrant
        onlyActiveBorrower(vault, msg.sender)
        validAmount(repayAmount)
        notInEmergencyMode
    {
        BorrowerPosition storage position = borrowers[vault][msg.sender];
        VaultConfig storage config = vaultConfigs[vault];

        _accrueInterest(vault);
        _updateBorrowerInterest(vault, msg.sender);

        uint256 totalDebt = position.borrowedAmount + position.accruedInterest;
        require(
            repayAmount > 0 && repayAmount <= totalDebt,
            "Invalid repay amount"
        );

        usdc.safeTransferFrom(msg.sender, address(this), repayAmount);

        // Calculate interest and principal portions
        uint256 interestPaid = Math.min(repayAmount, position.accruedInterest);
        uint256 principalPaid = repayAmount - interestPaid;

        // Split interest according to vault config
        uint256 vaultFee = interestPaid.mulDiv(
            config.vaultFeeRate,
            BASIS_POINTS,
            Math.Rounding.Floor
        );
        uint256 protocolFee = interestPaid.mulDiv(
            config.protocolFeeRate,
            BASIS_POINTS,
            Math.Rounding.Floor
        );
        uint256 lenderInterest = interestPaid - vaultFee - protocolFee;

        accruedVaultFees[vault] += vaultFee;
        accruedProtocolFees[vault] += protocolFee;
        position.accruedInterest -= interestPaid;
        position.borrowedAmount -= principalPaid;
        position.lastUpdateTime = block.timestamp;

        // Check if fully repaid
        bool isFullyRepaid = (position.borrowedAmount +
            position.accruedInterest ==
            0);
        uint256 collateralToReturn = 0;

        if (isFullyRepaid) {
            collateralToReturn = position.collateralAmount;
            position.collateralAmount = 0;
            position.isActive = false;
            vaultConfigs[vault].totalCollateral -= collateralToReturn;
            _removeActiveBorrower(vault, msg.sender);
        }

        // Update pool state
        vaultConfigs[vault].totalBorrowed -= principalPaid;

        // Return collateral if fully repaid
        if (collateralToReturn > 0) {
            IERC20Upgradeable(address(bubbleVault)).safeTransfer(
                msg.sender,
                collateralToReturn
            );
            emit CollateralReturned(
                vault,
                msg.sender,
                collateralToReturn,
                block.timestamp
            );
        }

        emit Repaid(
            vault,
            msg.sender,
            repayAmount,
            interestPaid,
            block.timestamp
        );
    }

    ///  Check if position is healthy
    function _isHealthy(
        address vault,
        address borrower,
        bool forLiquidation
    ) internal view returns (bool) {
        BorrowerPosition storage position = borrowers[vault][borrower];
        if (!position.isActive || position.collateralAmount == 0) return true;

        // (6 decimals)
        uint256 collateralValueUSDC = _getCollateralValue(
            position.collateralAmount
        );

        //  (6 decimals)
        uint256 totalDebtUSDC = position.borrowedAmount +
            _calculateBorrowerInterest(vault, borrower);

        if (totalDebtUSDC == 0) return true;

        uint256 threshold = forLiquidation
            ? vaultConfigs[vault].liquidationThreshold
            : vaultConfigs[vault].maxLTV;

        // LTV: debt/collateral * 10000
        uint256 currentLTV = totalDebtUSDC.mulDiv(
            BASIS_POINTS,
            collateralValueUSDC,
            Math.Rounding.Ceil
        );

        return currentLTV <= threshold;
    }

    ///  Liquidate unhealthy position
    /// @param borrower Address of borrower to liquidate
    function liquidate(address vault, address borrower)
        external
        nonReentrant
        notLiquidationsPaused
        onlyActiveBorrower(vault, borrower)
        notInEmergencyMode
    {
        require(liquidationEnabled, "Liquidation is disabled");
        require(vaultConfigs[vault].active, "Vault not active");

        _accrueInterest(vault);
        _updateBorrowerInterest(vault, borrower);

        require(!_isHealthy(vault, borrower, true), "Position is healthy");

        BorrowerPosition storage position = borrowers[vault][borrower];
        uint256 totalDebt = position.borrowedAmount + position.accruedInterest;
        uint256 collateralToLiquidate = position.collateralAmount;

        // Convert collateral to USDC
        uint256 usdcRecovered = _liquidateCollateral(vault, collateralToLiquidate);
        require(usdcRecovered > 0, "Liquidation failed");

        VaultConfig storage config = vaultConfigs[vault];

        // Calculate liquidation penalty
        uint256 penalty = usdcRecovered.mulDiv(
            config.liquidationPenalty,
            BASIS_POINTS,
            Math.Rounding.Floor
        );

        // Split penalty according to vault config
        uint256 vaultPenalty = penalty.mulDiv(
            config.vaultFeeRate,
            BASIS_POINTS,
            Math.Rounding.Floor
        );
        uint256 protocolPenalty = penalty.mulDiv(
            config.protocolFeeRate,
            BASIS_POINTS,
            Math.Rounding.Floor
        );
        uint256 lenderPenalty = penalty - vaultPenalty - protocolPenalty;

        // Update fees
        accruedVaultFees[vault] += vaultPenalty;
        accruedProtocolFees[vault] += protocolPenalty;

        // Distribute lender penalty to all active lenders
        if (lenderPenalty > 0 && vaultConfigs[vault].totalLent > 0) {
            address[] storage activeLenders = vaultActiveLenders[vault];
            for (uint256 i = 0; i < activeLenders.length; i++) {
                address lender = activeLenders[i];
                LenderInfo storage lenderInfo = vaultLenders[vault][lender];
                
                uint256 lenderShare = lenderPenalty.mulDiv(
                    lenderInfo.depositAmount,
                    vaultConfigs[vault].totalLent,
                    Math.Rounding.Floor
                );
                
                lenderInfo.accruedInterest += lenderShare;
            }
        }

        // Calculate debt repayment
        uint256 availableForDebt = usdcRecovered - penalty;
        uint256 debtRepayment = Math.min(totalDebt, availableForDebt);

        // Update position
        uint256 principalRepaid = Math.min(debtRepayment, position.borrowedAmount);
        uint256 interestRepaid = debtRepayment - principalRepaid;

        position.borrowedAmount -= principalRepaid;
        position.accruedInterest -= interestRepaid;
        position.collateralAmount = 0;
        position.isActive = false;

        // Update pool state
        vaultConfigs[vault].totalBorrowed -= principalRepaid;
        vaultConfigs[vault].totalCollateral -= collateralToLiquidate;

        _removeActiveBorrower(vault, borrower);

        counter = counter + 1;
        emit Liquidated(
            vault,
            borrower,
            msg.sender,
            collateralToLiquidate,
            debtRepayment,
            penalty,
            block.timestamp
        );
    }

    function liquidateMultiple(address vault, address[] calldata borrowersToLiquidate) external nonReentrant notLiquidationsPaused notInEmergencyMode {
        require(liquidationEnabled, "Liquidation is disabled");
        require(borrowersToLiquidate.length > 0, "No borrowers provided");
        require(borrowersToLiquidate.length <= 10, "Too many borrowers at once");

        uint256 totalLenderPenalty = 0;

        for (uint256 i = 0; i < borrowersToLiquidate.length; i++) {
            address borrower = borrowersToLiquidate[i];
            BorrowerPosition storage position = borrowers[vault][borrower];

            if (!position.isActive) continue;
            _updateBorrowerInterest(vault, borrower);
            if (_isHealthy(vault, borrower, true)) continue;

            uint256 totalDebt = position.borrowedAmount + position.accruedInterest;
            uint256 collateralToLiquidate = position.collateralAmount;

            uint256 usdcRecovered = _liquidateCollateral(vault, collateralToLiquidate);
            if (usdcRecovered == 0) continue;

            uint256 penalty = usdcRecovered.mulDiv(
                vaultConfigs[vault].liquidationPenalty,
                BASIS_POINTS,
                Math.Rounding.Floor
            );

            // Split penalty according to vault config
            uint256 vaultPenalty = penalty.mulDiv(
                vaultConfigs[vault].vaultFeeRate,
                BASIS_POINTS,
                Math.Rounding.Floor
            );
            uint256 protocolPenalty = penalty.mulDiv(
                vaultConfigs[vault].protocolFeeRate,
                BASIS_POINTS,
                Math.Rounding.Floor
            );
            uint256 lenderPenalty = penalty - vaultPenalty - protocolPenalty;

            accruedVaultFees[vault] += vaultPenalty;
            accruedProtocolFees[vault] += protocolPenalty;
            totalLenderPenalty += lenderPenalty;

            uint256 availableForDebt = usdcRecovered - penalty;
            uint256 debtRepayment = Math.min(totalDebt, availableForDebt);

            uint256 principalRepaid = Math.min(debtRepayment, position.borrowedAmount);
            uint256 interestRepaid = debtRepayment - principalRepaid;

            position.borrowedAmount -= principalRepaid;
            position.accruedInterest -= interestRepaid;
            position.collateralAmount = 0;
            position.isActive = false;

            _removeActiveBorrower(vault, borrower);

            vaultConfigs[vault].totalBorrowed -= principalRepaid;
            vaultConfigs[vault].totalCollateral -= collateralToLiquidate;

            counter = counter + 1;
            emit Liquidated(
                vault,
                borrower,
                msg.sender,
                collateralToLiquidate,
                debtRepayment,
                penalty,
                block.timestamp
            );
        }

        // Distribute total lender penalty to all active lenders
        if (totalLenderPenalty > 0 && vaultConfigs[vault].totalLent > 0) {
            address[] storage activeLenders = vaultActiveLenders[vault];
            for (uint256 i = 0; i < activeLenders.length; i++) {
                address lender = activeLenders[i];
                LenderInfo storage lenderInfo = vaultLenders[vault][lender];
                
                uint256 lenderShare = totalLenderPenalty.mulDiv(
                    lenderInfo.depositAmount,
                    vaultConfigs[vault].totalLent,
                    Math.Rounding.Floor
                );
                
                lenderInfo.accruedInterest += lenderShare;
            }
        }
    }

    /// Convert vault shares to USDC through liquidation
    function _liquidateCollateral(address vault, uint256 vaultShares)
        internal
        returns (uint256 usdcAmount)
    {
        if (vaultShares == 0) return 0;

        IERC20Upgradeable(address(bubbleVault)).approve(
            address(bubbleVault),
            vaultShares
        );

        (uint256 amountA, uint256 amountB) = bubbleVault.reclaim(
            vaultShares,
            address(this),
            address(this)
        );

        uint256 usdcFromA = _swapToUSDC(address(tokenA), amountA);
        uint256 usdcFromB = _swapToUSDC(address(tokenB), amountB);

        return usdcFromA + usdcFromB;
    }

    /// Swap token to USDC
    function _swapToUSDC(address token, uint256 amount)
        internal
        returns (uint256 usdcReceived)
    {
        if (amount == 0 || token == address(usdc)) return amount;

        IERC20Upgradeable(token).approve(address(octoRouter), amount);

        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = address(usdc);

        uint256[] memory amountsOut = octoRouter.getAmountsOut(amount, path);
        uint256 minOut = amountsOut[1].mulDiv(
            BASIS_POINTS - vaultConfigs[address(this)].slippageBPS,
            BASIS_POINTS,
            Math.Rounding.Floor
        );

        uint256[] memory swappedAmounts = octoRouter.swapExactTokensForTokens(
            amount,
            minOut,
            path,
            address(this),
            block.timestamp + 300
        );

        return swappedAmounts[1];
    }

    // INTEREST CALCULATION FUNCTIONS

    /// Calculate borrower interest
    function _calculateBorrowerInterest(address vault, address borrower)
        internal
        view
        returns (uint256)
    {
        BorrowerPosition storage position = borrowers[vault][borrower];
        if (!position.isActive || position.borrowedAmount == 0)
            return position.accruedInterest;

        uint256 timeElapsed = block.timestamp - position.lastUpdateTime;
         if (timeElapsed == 0) return position.accruedInterest;
        uint256 currentBorrowRate = getBorrowRate(vault);

        uint256 newInterest = position.borrowedAmount.mulDiv(
        currentBorrowRate.mulDiv(timeElapsed, 365 days, Math.Rounding.Ceil),
        BASIS_POINTS,
        Math.Rounding.Ceil
    );

        return position.accruedInterest + newInterest;
    }

    /// Calculate lender interest
    function _calculateLenderInterest(address vault, address lender)
        internal
        view
        returns (uint256)
    {
        LenderInfo storage info = vaultLenders[vault][lender];
        if (info.depositAmount == 0) return info.accruedInterest;

        uint256 timeElapsed = block.timestamp - info.lastUpdateTime;
        uint256 currentSupplyRate = getSupplyRate(vault);

        uint256 newInterest = info.depositAmount.mulDiv(
            currentSupplyRate * timeElapsed,
            BASIS_POINTS * 365 days,
            Math.Rounding.Floor
        );

        return info.accruedInterest + newInterest;
    }

    /// Update borrower interest
    function _updateBorrowerInterest(address vault, address borrower) internal {
        BorrowerPosition storage position = borrowers[vault][borrower];
        position.accruedInterest = _calculateBorrowerInterest(vault, borrower);
        position.lastUpdateTime = block.timestamp;
    }

    /// Update lender interest
    function _updateLenderInterest(address vault, address lender) internal {
        LenderInfo storage info = vaultLenders[vault][lender];
        if (info.depositAmount == 0) return;

        uint256 currentIndex = vaultInterestIndex[vault];
        uint256 lastIndex = lenderInterestIndex[vault][lender];
        
        if (currentIndex > lastIndex) {
            uint256 indexDelta = currentIndex - lastIndex;
            uint256 interestAccrued = info.depositAmount.mulDiv(
                indexDelta,
                1e18,
                Math.Rounding.Floor
            );
            info.accruedInterest += interestAccrued;
        }
        
        lenderInterestIndex[vault][lender] = currentIndex;
        info.lastUpdateTime = block.timestamp;
    }

    /// Accrue global interest
    function _accrueInterest(address vault) internal {
        uint256 timeElapsed = block.timestamp - lastAccrualTime;
        if (timeElapsed == 0) return;

        VaultConfig storage config = vaultConfigs[vault];

        // Calculate global interest rates
        uint256 borrowRate = getBorrowRate(vault);
        uint256 supplyRate = getSupplyRate(vault);

        // Update global interest index
        if (config.totalLent > 0) {
            uint256 interestAccrued = _calculateInterest(
                config.totalLent,
                supplyRate,
                timeElapsed
            );
            // Update interest index instead of adding to totalLent
            vaultInterestIndex[vault] += interestAccrued.mulDiv(
                1e18,
                config.totalLent,
                Math.Rounding.Floor
            );
        }

        // Accrue interest for all active borrowers
        address[] storage activeBorrowers = vaultActiveBorrowers[vault];
        for (uint256 i = 0; i < activeBorrowers.length; i++) {
            address borrower = activeBorrowers[i];
            BorrowerPosition storage position = borrowers[vault][borrower];

            if (position.isActive && position.borrowedAmount > 0) {
                uint256 interest = _calculateInterest(
                    position.borrowedAmount,
                    borrowRate,
                    timeElapsed
                );

                // Split interest according to vault config
                uint256 vaultFee = interest.mulDiv(
                    config.vaultFeeRate,
                    BASIS_POINTS,
                    Math.Rounding.Floor
                );
                uint256 protocolFee = interest.mulDiv(
                    config.protocolFeeRate,
                    BASIS_POINTS,
                    Math.Rounding.Floor
                );
                uint256 lenderInterest = interest - vaultFee - protocolFee;

                // Update fees
                accruedVaultFees[vault] += vaultFee;
                accruedProtocolFees[vault] += protocolFee;

                // Update position
                position.accruedInterest += interest;
                position.lastUpdateTime = block.timestamp;
            }
        }

        lastAccrualTime = block.timestamp;
    }

    function _calculateInterest(
        uint256 principal,
        uint256 rate,
        uint256 timeElapsed
    ) internal pure returns (uint256) {
        if (principal == 0 || rate == 0 || timeElapsed == 0) return 0;
        
        // Prevent overflow in multiplication
        if (rate > type(uint256).max / timeElapsed) {
            return principal.mulDiv(
                rate,
                365 days,
                Math.Rounding.Ceil
            ).mulDiv(
                timeElapsed,
                1,
                Math.Rounding.Ceil
            );
        }
        
        return principal.mulDiv(
            rate * timeElapsed,
            BASIS_POINTS * 365 days,
            Math.Rounding.Ceil
        );
    }

    function updateInterestRateModel(
        address vault,
        uint256 _baseRate,
        uint256 _multiplier,
        uint256 _jumpMultiplier,
        uint256 _kink
    ) external onlyOwner {
        require(_kink <= BASIS_POINTS, "Invalid kink");
        require(_baseRate <= 2000, "Base rate too high"); // Max 20%

        VaultConfig storage config = vaultConfigs[vault];
        config.baseRate = _baseRate;
        config.multiplier = _multiplier;
        config.jumpMultiplier = _jumpMultiplier;
        config.kink = _kink;

        emit InterestRateModelUpdated(
            vault,
            _baseRate,
            _multiplier,
            _jumpMultiplier,
            _kink
        );
    }

    /// Get current rates for display
    function getCurrentRates(address vault)
        external
        view
        returns (
            uint256 utilization,
            uint256 borrowRate,
            uint256 supplyRate
        )
    {
        utilization = getUtilizationRate(vault);
        borrowRate = getBorrowRate(vault);
        supplyRate = getSupplyRate(vault);
    }

    /// Get rate at specific utilization (for frontend curves)
    function getRateAtUtilization(address vault, uint256 utilizationRate)
        external
        view
        returns (uint256 borrowRate, uint256 supplyRate)
    {
        // Temporarily calculate rates at given utilization
        if (utilizationRate <= vaultConfigs[vault].kink) {
            borrowRate =
                vaultConfigs[vault].baseRate +
                utilizationRate.mulDiv(
                    vaultConfigs[vault].multiplier,
                    BASIS_POINTS,
                    Math.Rounding.Floor
                );
        } else {
            uint256 normalRate = vaultConfigs[vault].baseRate +
                vaultConfigs[vault].kink.mulDiv(
                    vaultConfigs[vault].multiplier,
                    BASIS_POINTS,
                    Math.Rounding.Floor
                );
            uint256 excessUtil = utilizationRate - vaultConfigs[vault].kink;
            uint256 jumpRate = excessUtil.mulDiv(
                vaultConfigs[vault].jumpMultiplier,
                BASIS_POINTS,
                Math.Rounding.Floor
            );
            borrowRate = normalRate + jumpRate;
        }

        uint256 rateToPool = borrowRate.mulDiv(
            vaultConfigs[vault].lenderShare,
            BASIS_POINTS,
            Math.Rounding.Floor
        );
        supplyRate = utilizationRate.mulDiv(
            rateToPool,
            BASIS_POINTS,
            Math.Rounding.Floor
        );
    }

    ///  Get borrower position with current interest
    function getBorrowerPosition(address vault, address borrower)
        external
        view
        returns (BorrowerPosition memory position)
    {
        position = borrowers[vault][borrower];
        position.accruedInterest = _calculateBorrowerInterest(vault, borrower);
    }

    ///  Get lender info with current interest
    function getLenderInfo(address vault, address lender)
        external
        view
        returns (LenderInfo memory info)
    {
        info = vaultLenders[vault][lender];
        info.accruedInterest = _calculateLenderInterest(vault, lender);
    }

    ///  Check if position can be liquidated
    function canLiquidate(address vault, address borrower)
        external
        view
        returns (bool)
    {
        BorrowerPosition storage position = borrowers[vault][borrower];
        if (!position.isActive) return false;
        return !_isHealthy(vault, borrower, true);
    }

    ///  Get health factor
    function getHealthFactor(address vault, address borrower)
        external
        view
        returns (uint256)
    {
        BorrowerPosition storage position = borrowers[vault][borrower];
        if (!position.isActive) return type(uint256).max;

        uint256 collateralValueUSDC = _getCollateralValue(
            position.collateralAmount
        );
        uint256 totalDebtUSDC = position.borrowedAmount +
            _calculateBorrowerInterest(vault, borrower);

        if (totalDebtUSDC == 0) return type(uint256).max;

        return
            collateralValueUSDC.mulDiv(
                vaultConfigs[vault].liquidationThreshold,
                totalDebtUSDC,
                Math.Rounding.Floor
            );
    }

    ///  Get collateral value in USDC (6 decimals for display)
    function getCollateralValueInUSDC(address vault, uint256 vaultShares)
        external
        view
        returns (uint256)
    {
        return _getCollateralValue(vaultShares);
    }

    ///  Get current token price in USDC (6 decimals for display)
    function getTokenPrice(address vault, address token)
        external
        view
        returns (uint256)
    {
        uint256 priceIn18Decimals = _getTokenPriceInUSDC(token);
        return _fromCalculationDecimals(priceIn18Decimals);
    }

    ///  Get current prices for WMON and SHMON
    function getCurrentPrices()
        external
        view
        returns (uint256 wmonPrice, uint256 shmonPrice)
    {
        uint256 wmonInternal = _getTokenPriceInUSDC(WMON_ADDRESS);
        uint256 shmonInternal = _getTokenPriceInUSDC(SHMON_ADDRESS);

        wmonPrice = _fromCalculationDecimals(wmonInternal);
        shmonPrice = _fromCalculationDecimals(shmonInternal);
    }

    ///  Get underlying tokens for vault shares
    function getUnderlyingTokens(address vault, uint256 vaultShares)
        external
        view
        returns (uint256 tokenAAmount, uint256 tokenBAmount)
    {
        if (vaultShares == 0) return (0, 0);
        uint256 lpTokenAmount = bubbleVault.previewRedeem(vaultShares);
        return _calculateTokenAmountsFromLP(lpTokenAmount);
    }

    ///  Withdraw protocol or vault fees
    function withdrawFees(
        address vault,
        uint256 amount,
        bool isProtocol
    ) external onlyOwner {
        if (isProtocol) {
            require(
                amount <= accruedProtocolFees[vault],
                "Insufficient protocol fees"
            );
            accruedProtocolFees[vault] -= amount;
            usdc.safeTransfer(protocolFeeRecipient, amount);
        } else {
            require(
                amount <= accruedVaultFees[vault],
                "Insufficient vault fees"
            );
            accruedVaultFees[vault] -= amount;
            usdc.safeTransfer(vaultFeeRecipient[vault], amount);
        }
    }

    ///   token recovery
    function recoverTokens(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        require(to != address(0), "Invalid recipient");

        IERC20Upgradeable tokenContract = IERC20Upgradeable(token);
        uint256 balance = tokenContract.balanceOf(address(this));
        require(balance > 0, "No tokens to recover");

        if (amount == 0) amount = balance;
        else require(amount <= balance, "Insufficient token balance");

        tokenContract.safeTransfer(to, amount);
        emit TokensRecovered(token, to, amount);
    }

    function checker(address vault)
        external
        view
        returns (bool canExec, bytes memory execPayload)
    {
        // Get liquidatable positions (max 5 for gas efficiency)
        address[] memory liquidatablePositions = getLiquidatablePositions(
            vault,
            5
        );

        if (liquidatablePositions.length > 0) {
            // Prepare execution data for batch liquidation
            execPayload = abi.encodeWithSelector(
                this.liquidateMultiple.selector,
                liquidatablePositions
            );
            canExec = true;
        } else {
            canExec = false;
            execPayload = bytes("");
        }
    }

    function checkerSingle(address vault)
        external
        view
        returns (bool canExec, bytes memory execPayload)
    {
        address liquidatablePosition = getFirstLiquidatablePosition(vault);

        if (liquidatablePosition != address(0)) {
            execPayload = abi.encodeWithSelector(
                this.liquidate.selector,
                vault,
                liquidatablePosition
            );
            canExec = true;
        } else {
            canExec = false;
            execPayload = bytes("");
        }
    }

    function setVaultHardcodedYield(address vault, uint256 yieldBPS)
        external
        onlyOwner
    {
        require(vault != address(0), "Invalid vault address");
        require(yieldBPS <= BASIS_POINTS, "Yield too high");
        vaultHardcodedYield[vault] = yieldBPS;
    }

    function _addActiveLender(address vault, address lender) internal {
        if (
            vaultLenderIndex[vault][lender] == 0 &&
            (vaultActiveLenders[vault].length == 0 ||
                vaultActiveLenders[vault][0] != lender)
        ) {
            vaultActiveLenders[vault].push(lender);
            vaultLenderIndex[vault][lender] = vaultActiveLenders[vault].length;
        }
    }

    function _removeActiveLender(address vault, address lender) internal {
        uint256 index = vaultLenderIndex[vault][lender];
        if (index == 0) return;

        uint256 arrayIndex = index - 1;
        uint256 lastIndex = vaultActiveLenders[vault].length - 1;

        if (arrayIndex != lastIndex) {
            address lastLender = vaultActiveLenders[vault][lastIndex];
            vaultActiveLenders[vault][arrayIndex] = lastLender;
            vaultLenderIndex[vault][lastLender] = index;
        }

        vaultActiveLenders[vault].pop();
        delete vaultLenderIndex[vault][lender];
    }

    // OWNER FUNCTIONS FOR FEE RECIPIENTS AND CAPS
    function setProtocolFeeRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), "Invalid address");
        protocolFeeRecipient = recipient;
    }

    function setVaultFeeRecipient(address vault, address recipient)
        external
        onlyOwner
    {
        require(
            vault != address(0) && recipient != address(0),
            "Invalid address"
        );
        vaultFeeRecipient[vault] = recipient;
    }

    function setGlobalMaxBorrow(uint256 cap) external onlyOwner {
        globalMaxBorrow = cap;
    }

    function setVaultMaxBorrow(address vault, uint256 cap) external onlyOwner {
        require(vault != address(0), "Invalid vault");
        vaultMaxBorrow[vault] = cap;
    }

    function getTotalBorrowedAllVaults() public view returns (uint256 total) {
        for (uint256 i = 0; i < activeVaults.length; i++) {
            address vault = activeVaults[i];
            if (vaultConfigs[vault].active) {
                total += vaultConfigs[vault].totalBorrowed;
            }
        }
    }

    function setMaxUtilizationOnWithdraw(uint256 bps) external onlyOwner {
        require(bps <= BASIS_POINTS, "Too high");
        maxUtilizationOnWithdraw = bps;
    }

    function setEmergencyMode(bool _emergencyMode) external onlyOwner {
        emergencyMode = _emergencyMode;
    }

    fallback() external {}
}
