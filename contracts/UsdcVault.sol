// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IPawUsdc.sol";
import "./interfaces/IBubbleVault.sol";
import "./interfaces/IMonadPriceFetcher.sol";
import "./vaultV1uups.sol";
import "./bubbleFiABI.sol";
import "./uniswaphelper.sol";

contract USDCVault is
    Initializable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;
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
        uint256 liquidationVaultShare;    // Added for liquidation fee distribution
        uint256 liquidationProtocolShare; // Added for liquidation fee distribution
        uint256 liquidationLenderShare;   // Added for liquidation fee distribution
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

    IPawUSDC public pawUSDC;
    IBubbleVault public bubbleVault;
    IERC20 public usdc;
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
    VaultConfig public config;
    mapping(address => LenderInfo) public lenders;
    mapping(address => BorrowerPosition) public borrowers;
    address[] public activeBorrowers;
    mapping(address => uint256) public borrowerIndex;
    address[] public activeLenders;
    mapping(address => uint256) public lenderIndex;
    uint256 public vaultInterestIndex;
    mapping(address => uint256) public lenderInterestIndex;

    IERC20 public tokenA;
    IERC20 public tokenB;
    IERC20 public lpToken;
    IOctoswapRouter02 public octoRouter;
    IBubbleV1Router public bubbleRouter;

    uint256 public lastAccrualTime;
    uint256 public counter;

    uint256 public accumulatedFees;
    bool public liquidationEnabled;
    bool public borrowingPaused;
    bool public liquidationsPaused;
    bool public emergencyMode;

    // Fee recipient addresses and borrow caps
    address public protocolFeeRecipient;
    address public vaultFeeRecipient;
    uint256 public maxBorrow;
    uint256 public accruedVaultFees;
    uint256 public accruedProtocolFees;
    uint256 public maxUtilizationOnWithdraw;
    uint256 public vaultHardcodedYield; // Added for yield-based rate calculation

    // NEW: Track lender interest distribution
    uint256 public totalLenderInterest;
    uint256 public globalLenderInterestIndex;

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
    event Borrowed(
        address indexed borrower,
        uint256 collateral,
        uint256 borrowAmount,
        uint256 timestamp
    );
    event Repaid(
        address indexed borrower,
        uint256 repayAmount,
        uint256 interest,
        uint256 timestamp
    );
    event Liquidated(
        address indexed borrower,
        address indexed liquidator,
        uint256 collateralLiquidated,
        uint256 debtRepaid,
        uint256 penalty,
        uint256 timestamp
    );
    event CollateralReturned(
        address indexed borrower,
        uint256 collateralAmount,
        uint256 timestamp
    );
    event InterestRateModelUpdated(
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
        address indexed borrower,
        uint256 amount,
        uint256 timestamp
    );
    event MaxUtilizationOnWithdrawUpdated(uint256 oldValue, uint256 newValue);
    event VaultHardcodedYieldUpdated(uint256 oldValue, uint256 newValue);
    event MaxBorrowUpdated(uint256 oldValue, uint256 newValue);

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _usdc,
        address _priceFetcher,
        address _pawUSDC,
        address _bubbleVault,
        address _tokenA,
        address _tokenB,
        address _owner,
        uint256 _maxLTV,
        uint256 _liquidationThreshold,
        uint256 _liquidationPenalty,
        uint256 _baseRate,
        uint256 _multiplier,
        uint256 _jumpMultiplier,
        uint256 _kink,
        uint256 _protocolFeeRate,
        uint256 _vaultFeeRate,
        uint256 _lenderShare,
        uint256 _slippageBPS,
        address _lpToken,
        address _octoRouter,
        address _bubbleRouter,
        uint256 _liquidationVaultShare,
        uint256 _liquidationProtocolShare,
        uint256 _liquidationLenderShare
    ) public initializer {
        require(_usdc != address(0), "Invalid USDC address");
        require(_priceFetcher != address(0), "Invalid price fetcher address");
        require(_pawUSDC != address(0), "Invalid PawUSDC address");
        require(_bubbleVault != address(0), "Invalid BubbleVault address");
        require(_owner != address(0), "Invalid owner address");
        require(_tokenA != address(0), "Invalid token A address");
        require(_tokenB != address(0), "Invalid token B address");
        require(_lpToken != address(0), "Invalid LP token address");
        require(address(_octoRouter) != address(0), "Invalid octo router address");
        require(address(_bubbleRouter) != address(0), "Invalid bubble router address");
        require(_maxLTV <= _liquidationThreshold, "Invalid LTV configuration");
        require(_kink <= BASIS_POINTS, "Invalid kink value");
        require(_protocolFeeRate <= BASIS_POINTS, "Invalid protocol fee rate");
        require(_lenderShare <= BASIS_POINTS, "Invalid lender share");
        require(_slippageBPS <= BASIS_POINTS, "Invalid slippage value");
        require(
            _liquidationVaultShare + _liquidationProtocolShare + _liquidationLenderShare == BASIS_POINTS,
            "Invalid liquidation fee distribution"
        );

        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        usdc = IERC20(_usdc);
        priceFetcher = IMonadPriceFetcher(_priceFetcher);
        pawUSDC = IPawUSDC(_pawUSDC);
        bubbleVault = IBubbleVault(_bubbleVault);
        lastAccrualTime = block.timestamp;
        counter = 0;
        vaultInterestIndex = 1e18; // Initialize to 1
        globalLenderInterestIndex = 0;

        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
        lpToken = IERC20(_lpToken);

        config = VaultConfig({
            maxLTV: _maxLTV,
            liquidationThreshold: _liquidationThreshold,
            liquidationPenalty: _liquidationPenalty,
            baseRate: _baseRate,
            multiplier: _multiplier,
            jumpMultiplier: _jumpMultiplier,
            kink: _kink,
            borrowingEnabled: true,
            active: true,
            totalLent: 0,
            totalBorrowed: 0,
            totalCollateral: 0,
            protocolFeeRate: _protocolFeeRate,
            vaultFeeRate: _vaultFeeRate,
            lenderShare: _lenderShare,
            slippageBPS: _slippageBPS,
            minBorrowAmount: 100,
            minLiquidationAmount: 100,
            liquidationVaultShare: _liquidationVaultShare,
            liquidationProtocolShare: _liquidationProtocolShare,
            liquidationLenderShare: _liquidationLenderShare
        });

        maxUtilizationOnWithdraw = 9500; // 95% by default
    }

    // MODIFIERS
    modifier validAmount(uint256 amount) {
        require(amount > 0, "Amount must be greater than 0");
        _;
    }

    modifier onlyActiveBorrower(address borrower) {
        require(borrowers[borrower].isActive, "No active position");
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

    // INTERNAL FUNCTIONS
    function _addActiveBorrower(address borrower) internal {
        if (
            borrowerIndex[borrower] == 0 &&
            (activeBorrowers.length == 0 || activeBorrowers[0] != borrower)
        ) {
            activeBorrowers.push(borrower);
            borrowerIndex[borrower] = activeBorrowers.length;
        }
    }

    function _removeActiveBorrower(address borrower) internal {
        uint256 index = borrowerIndex[borrower];
        if (index == 0) return;

        uint256 arrayIndex = index - 1;
        uint256 lastIndex = activeBorrowers.length - 1;

        if (arrayIndex != lastIndex) {
            address lastBorrower = activeBorrowers[lastIndex];
            activeBorrowers[arrayIndex] = lastBorrower;
            borrowerIndex[lastBorrower] = index;
        }

        activeBorrowers.pop();
        delete borrowerIndex[borrower];
    }

    function _addActiveLender(address lender) internal {
        if (
            lenderIndex[lender] == 0 &&
            (activeLenders.length == 0 || activeLenders[0] != lender)
        ) {
            activeLenders.push(lender);
            lenderIndex[lender] = activeLenders.length;
        }
    }

    function _removeActiveLender(address lender) internal {
        uint256 index = lenderIndex[lender];
        if (index == 0) return;

        uint256 arrayIndex = index - 1;
        uint256 lastIndex = activeLenders.length - 1;

        if (arrayIndex != lastIndex) {
            address lastLender = activeLenders[lastIndex];
            activeLenders[arrayIndex] = lastLender;
            lenderIndex[lastLender] = index;
        }

        activeLenders.pop();
        delete lenderIndex[lender];
    }

    // CORE FUNCTIONS
    function lendUSDC(
        uint256 amount
    ) external nonReentrant validAmount(amount) notInEmergencyMode {
        require(amount >= MIN_DEPOSIT_AMOUNT, "Amount too small");
        require(amount <= MAX_DEPOSIT_AMOUNT, "Amount too large");
        require(config.active, "Vault not active");

        _accrueInterest();

        LenderInfo storage lender = lenders[msg.sender];
        if (lender.depositAmount > 0) {
            _updateLenderInterest(msg.sender);
        } else {
            // Initialize interest index for new lender
            lenderInterestIndex[msg.sender] = globalLenderInterestIndex;
        }

        lender.depositAmount += amount;
        lender.lastUpdateTime = block.timestamp;
        config.totalLent += amount;

        _addActiveLender(msg.sender);

        usdc.safeTransferFrom(msg.sender, address(this), amount);

        // Mint PawUSDC to lender
        pawUSDC.mint(msg.sender, amount);
        lender.pawUSDCAmount += amount;

        emit LentUSDC(msg.sender, amount, amount, block.timestamp);
    }

    function withdrawUSDC(
        uint256 amount
    ) external nonReentrant notInEmergencyMode {
        LenderInfo storage lender = lenders[msg.sender];
        require(lender.depositAmount > 0, "No deposit found");

        _accrueInterest();
        _updateLenderInterest(msg.sender);

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
        uint256 newTotalLent = config.totalLent - amount;
        uint256 utilizationAfter = newTotalLent == 0
            ? 0
            : config.totalBorrowed.mulDiv(
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

        // Update vault state
        config.totalLent -= amount;
        totalLenderInterest -= interestToWithdraw;

        // Remove from active lenders if fully withdrawn
        if (lender.depositAmount == 0) {
            _removeActiveLender(msg.sender);
        }

        // Burn PawUSDC tokens
        pawUSDC.burn(msg.sender, amount);
        lender.pawUSDCAmount -= amount;

        // Move the transfer to the end after all state changes
        usdc.safeTransfer(msg.sender, totalWithdraw);

        emit WithdrewUSDC(
            msg.sender,
            amount,
            interestToWithdraw,
            block.timestamp
        );
    }

    function borrow(
        uint256 collateralAmount,
        uint256 borrowAmount
    )
        external
        nonReentrant
        notBorrowingPaused
        validAmount(borrowAmount)
        notInEmergencyMode
    {
        require(config.active, "Vault not active");
        require(config.borrowingEnabled, "Borrowing disabled");
        require(
            usdc.balanceOf(address(this)) >= borrowAmount,
            "Insufficient liquidity"
        );

        _accrueInterest();

        // Enforce max borrow cap
        uint256 newTotalBorrowed = config.totalBorrowed + borrowAmount;
        require(
            maxBorrow == 0 || newTotalBorrowed <= maxBorrow,
            "Exceeds max borrow cap"
        );

        BorrowerPosition storage position = borrowers[msg.sender];

        if (collateralAmount > 0) {
            require(
                IERC20(address(bubbleVault)).balanceOf(msg.sender) >=
                    collateralAmount,
                "Insufficient vault shares balance"
            );

            IERC20(address(bubbleVault)).safeTransferFrom(
                msg.sender,
                address(this),
                collateralAmount
            );
        }

        uint256 totalBorrowAmount = borrowAmount;
        uint256 totalCollateralAmount = collateralAmount;

        if (position.isActive) {
            _updateBorrowerInterest(msg.sender);

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
            config.maxLTV,
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
            _addActiveBorrower(msg.sender);
        }
        position.lastUpdateTime = block.timestamp;

        require(
            _isHealthy(msg.sender, false),
            "Position unhealthy after borrow"
        );

        // Update pool state
        config.totalCollateral += collateralAmount;
        config.totalBorrowed += borrowAmount;

        usdc.safeTransfer(msg.sender, borrowAmount);
        emit Borrowed(
            msg.sender,
            collateralAmount,
            borrowAmount,
            block.timestamp
        );
    }

    function repay(
        uint256 repayAmount
    )
        external
        nonReentrant
        onlyActiveBorrower(msg.sender)
        validAmount(repayAmount)
        notInEmergencyMode
    {
        BorrowerPosition storage position = borrowers[msg.sender];

        _accrueInterest();
        _updateBorrowerInterest(msg.sender);

        uint256 totalDebt = position.borrowedAmount + position.accruedInterest;
        require(
            repayAmount > 0 && repayAmount <= totalDebt,
            "Invalid repay amount"
        );

        usdc.safeTransferFrom(msg.sender, address(this), repayAmount);

        // Calculate interest and principal portions
        uint256 interestPaid = Math.min(repayAmount, position.accruedInterest);
        uint256 principalPaid = repayAmount - interestPaid;

        // FIXED: Proper fee distribution for interest payments
        if (interestPaid > 0) {
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

            // Update fee accumulations
            accruedVaultFees += vaultFee;
            accruedProtocolFees += protocolFee;

            // Distribute to lenders through interest index
            if (lenderInterest > 0 && config.totalLent > 0) {
                totalLenderInterest += lenderInterest;
                globalLenderInterestIndex += lenderInterest.mulDiv(
                    1e18,
                    config.totalLent,
                    Math.Rounding.Floor
                );
            }
        }

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
            config.totalCollateral -= collateralToReturn;
            _removeActiveBorrower(msg.sender);
        }

        // Update pool state
        config.totalBorrowed -= principalPaid;

        // Return collateral if fully repaid
        if (collateralToReturn > 0) {
            IERC20(address(bubbleVault)).safeTransfer(
                msg.sender,
                collateralToReturn
            );
            emit CollateralReturned(
                msg.sender,
                collateralToReturn,
                block.timestamp
            );
        }

        emit Repaid(msg.sender, repayAmount, interestPaid, block.timestamp);
    }

    function liquidate(
        address borrower
    )
        external
        nonReentrant
        notLiquidationsPaused
        onlyActiveBorrower(borrower)
        notInEmergencyMode
    {
        require(liquidationEnabled, "Liquidation is disabled");
        require(config.active, "Vault not active");

        _accrueInterest();
        _updateBorrowerInterest(borrower);

        require(!_isHealthy(borrower, true), "Position is healthy");

        BorrowerPosition storage position = borrowers[borrower];
        uint256 totalDebt = position.borrowedAmount + position.accruedInterest;
        uint256 collateralToLiquidate = position.collateralAmount;

        // Convert collateral to USDC
        uint256 usdcRecovered = _liquidateCollateral(collateralToLiquidate);
        require(usdcRecovered > 0, "Liquidation failed");

        // Calculate liquidation penalty
        uint256 penalty = usdcRecovered.mulDiv(
            config.liquidationPenalty,
            BASIS_POINTS,
            Math.Rounding.Floor
        );

        // Use config values for liquidation penalty distribution
        uint256 vaultPenalty = penalty.mulDiv(
            config.liquidationVaultShare,
            BASIS_POINTS,
            Math.Rounding.Floor
        );
        uint256 protocolPenalty = penalty.mulDiv(
            config.liquidationProtocolShare,
            BASIS_POINTS,
            Math.Rounding.Floor
        );
        uint256 lenderPenalty = penalty.mulDiv(
            config.liquidationLenderShare,
            BASIS_POINTS,
            Math.Rounding.Floor
        );

        // Update fees
        accruedVaultFees += vaultPenalty;
        accruedProtocolFees += protocolPenalty;

        // Distribute lender penalty through interest index
        if (lenderPenalty > 0 && config.totalLent > 0) {
            totalLenderInterest += lenderPenalty;
            globalLenderInterestIndex += lenderPenalty.mulDiv(
                1e18,
                config.totalLent,
                Math.Rounding.Floor
            );
        }

        // Calculate debt repayment
        uint256 availableForDebt = usdcRecovered - penalty;
        uint256 debtRepayment = Math.min(totalDebt, availableForDebt);

        // Update position
        uint256 principalRepaid = Math.min(
            debtRepayment,
            position.borrowedAmount
        );
        uint256 interestRepaid = debtRepayment - principalRepaid;

        position.borrowedAmount -= principalRepaid;
        position.accruedInterest -= interestRepaid;
        position.collateralAmount = 0;
        position.isActive = false;

        // Update pool state
        config.totalBorrowed -= principalRepaid;
        config.totalCollateral -= collateralToLiquidate;

        _removeActiveBorrower(borrower);

        counter = counter + 1;
        emit Liquidated(
            borrower,
            msg.sender,
            collateralToLiquidate,
            debtRepayment,
            penalty,
            block.timestamp
        );
    }

    // INTEREST CALCULATION FUNCTIONS
    function _calculateBorrowerInterest(
        address borrower
    ) internal view returns (uint256) {
        BorrowerPosition storage position = borrowers[borrower];
        if (!position.isActive || position.borrowedAmount == 0)
            return position.accruedInterest;

        uint256 timeElapsed = block.timestamp - position.lastUpdateTime;
        if (timeElapsed == 0) return position.accruedInterest;
        uint256 currentBorrowRate = getBorrowRate();

        uint256 newInterest = position.borrowedAmount.mulDiv(
            currentBorrowRate.mulDiv(timeElapsed, 365 days, Math.Rounding.Ceil),
            BASIS_POINTS,
            Math.Rounding.Ceil
        );

        return position.accruedInterest + newInterest;
    }

    function _updateBorrowerInterest(address borrower) internal {
        BorrowerPosition storage position = borrowers[borrower];
        position.accruedInterest = _calculateBorrowerInterest(borrower);
        position.lastUpdateTime = block.timestamp;
    }

    function _updateLenderInterest(address lender) internal {
        LenderInfo storage info = lenders[lender];
        if (info.depositAmount == 0) return;

        uint256 currentIndex = globalLenderInterestIndex;
        uint256 lastIndex = lenderInterestIndex[lender];

        if (currentIndex > lastIndex) {
            uint256 indexDelta = currentIndex - lastIndex;
            uint256 interestAccrued = info.depositAmount.mulDiv(
                indexDelta,
                1e18,
                Math.Rounding.Floor
            );
            info.accruedInterest += interestAccrued;
        }

        lenderInterestIndex[lender] = currentIndex;
        info.lastUpdateTime = block.timestamp;
    }

    function _accrueInterest() internal {
        uint256 timeElapsed = block.timestamp - lastAccrualTime;
        if (timeElapsed == 0) return;

        uint256 borrowRate = getBorrowRate();

        // FIXED: Process borrower interest and distribute fees properly
        uint256 totalInterestGenerated = 0;

        for (uint256 i = 0; i < activeBorrowers.length; i++) {
            address borrower = activeBorrowers[i];
            BorrowerPosition storage position = borrowers[borrower];

            if (position.isActive && position.borrowedAmount > 0) {
                uint256 interest = _calculateInterest(
                    position.borrowedAmount,
                    borrowRate,
                    timeElapsed
                );

                totalInterestGenerated += interest;
                position.accruedInterest += interest;
                position.lastUpdateTime = block.timestamp;
            }
        }

        // Distribute generated interest
        if (totalInterestGenerated > 0) {
            uint256 vaultFee = totalInterestGenerated.mulDiv(
                config.vaultFeeRate,
                BASIS_POINTS,
                Math.Rounding.Floor
            );
            uint256 protocolFee = totalInterestGenerated.mulDiv(
                config.protocolFeeRate,
                BASIS_POINTS,
                Math.Rounding.Floor
            );
            uint256 lenderInterest = totalInterestGenerated -
                vaultFee -
                protocolFee;

            // Update fee accumulations
            accruedVaultFees += vaultFee;
            accruedProtocolFees += protocolFee;

            // Update lender interest index
            if (lenderInterest > 0 && config.totalLent > 0) {
                totalLenderInterest += lenderInterest;
                globalLenderInterestIndex += lenderInterest.mulDiv(
                    1e18,
                    config.totalLent,
                    Math.Rounding.Floor
                );
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

        uint256 yearInSeconds = 31557600; // 365.25 * 24 * 60 * 60

        return
            principal.mulDiv(
                rate * timeElapsed,
                BASIS_POINTS * yearInSeconds,
                Math.Rounding.Ceil
            );
    }

    /// Get token price in USDC using oracle
    /// @return price Price in calculation decimals (18 decimals) representing USDC value per token
    function _getTokenPriceInUSDC(
        address token
    ) internal view returns (uint256 price) {
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

    /// Convert USDC (6 decimals) to calculation format (18 decimals)
    function _toCalculationDecimals(
        uint256 usdcAmount
    ) private pure returns (uint256) {
        return usdcAmount * USDC_TO_CALC_SCALE;
    }

    /// Convert calculation format (18 decimals) to USDC (6 decimals)
    function _fromCalculationDecimals(
        uint256 calcAmount
    ) private pure returns (uint256) {
        return calcAmount / USDC_TO_CALC_SCALE;
    }

    /// Get collateral value in USDC
    /// @param vaultShares Amount of vault shares
    /// @return value Total value in USDC (6 decimals)
    function _getCollateralValue(
        uint256 vaultShares
    ) internal view returns (uint256 value) {
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
    function _calculateTokenAmountsFromLP(
        uint256 lpTokenAmount
    ) internal view returns (uint256 tokenAAmount, uint256 tokenBAmount) {
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

    /// Convert vault shares to USDC through liquidation
    function _liquidateCollateral(
        uint256 vaultShares
    ) internal returns (uint256 usdcAmount) {
        if (vaultShares == 0) return 0;

        IERC20(address(bubbleVault)).approve(address(bubbleVault), vaultShares);

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
    function _swapToUSDC(
        address token,
        uint256 amount
    ) internal returns (uint256 usdcReceived) {
        if (amount == 0 || token == address(usdc)) return amount;

        IERC20(token).approve(address(octoRouter), amount);

        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = address(usdc);

        uint256[] memory amountsOut = octoRouter.getAmountsOut(amount, path);
        uint256 minOut = amountsOut[1].mulDiv(
            BASIS_POINTS - config.slippageBPS,
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

    // VIEW FUNCTIONS
    function getUtilizationRate() public view returns (uint256) {
        if (config.totalLent == 0) return 0;
        return
            config.totalBorrowed.mulDiv(
                BASIS_POINTS,
                config.totalLent,
                Math.Rounding.Floor
            );
    }

    function getBorrowRate() public view returns (uint256) {
        require(config.active, "Vault not active");

        uint256 utilization = getUtilizationRate();

        uint256 yieldGenerated = (vaultHardcodedYield > 0)
            ? vaultHardcodedYield
            : DEFAULT_BASE_RATE;

        uint256 baseBorrowRate = yieldGenerated / 3;

        if (utilization <= config.kink) {
            // Below kink: linear scale of baseBorrowRate by utilization
            return
                baseBorrowRate.mulDiv(
                    utilization,
                    BASIS_POINTS,
                    Math.Rounding.Floor
                );
        } else {
            // Above kink: normal rate at kink + jump rate for excess utilization
            uint256 normalRateAtKink = baseBorrowRate.mulDiv(
                config.kink,
                BASIS_POINTS,
                Math.Rounding.Floor
            );

            uint256 excessUtil = utilization - config.kink;

            uint256 jumpRate = excessUtil.mulDiv(
                config.jumpMultiplier,
                BASIS_POINTS,
                Math.Rounding.Floor
            );

            return normalRateAtKink + jumpRate;
        }
    }

    function getSupplyRate() public view returns (uint256) {
        uint256 utilization = getUtilizationRate();
        uint256 borrowRate = getBorrowRate();

        uint256 rateToPool = borrowRate.mulDiv(
            config.lenderShare,
            BASIS_POINTS,
            Math.Rounding.Floor
        );
        return
            utilization.mulDiv(rateToPool, BASIS_POINTS, Math.Rounding.Floor);
    }

    function _isHealthy(
        address borrower,
        bool forLiquidation
    ) internal view returns (bool) {
        BorrowerPosition storage position = borrowers[borrower];
        if (!position.isActive || position.collateralAmount == 0) return true;

        uint256 collateralValueUSDC = _getCollateralValue(
            position.collateralAmount
        );

        uint256 totalDebtUSDC = position.borrowedAmount +
            _calculateBorrowerInterest(borrower);

        if (totalDebtUSDC == 0) return true;

        uint256 threshold = forLiquidation
            ? config.liquidationThreshold
            : config.maxLTV;

        uint256 currentLTV = totalDebtUSDC.mulDiv(
            BASIS_POINTS,
            collateralValueUSDC,
            Math.Rounding.Ceil
        );

        return currentLTV <= threshold;
    }

    // ADMIN FUNCTIONS
    function setLiquidationEnabled(bool _enabled) external onlyOwner {
        liquidationEnabled = _enabled;
    }

    function setBorrowingPaused(bool _paused) external onlyOwner {
        borrowingPaused = _paused;
    }

    function setLiquidationsPaused(bool _paused) external onlyOwner {
        liquidationsPaused = _paused;
    }

    function setEmergencyMode(bool _emergencyMode) external onlyOwner {
        emergencyMode = _emergencyMode;
    }

    function setMaxBorrow(uint256 _maxBorrow) external onlyOwner {
        uint256 oldValue = maxBorrow;
        maxBorrow = _maxBorrow;
        emit MaxBorrowUpdated(oldValue, _maxBorrow);
    }

    function setMaxUtilizationOnWithdraw(uint256 bps) external onlyOwner {
        require(bps <= BASIS_POINTS, "Utilization rate too high");
        require(bps >= 5000, "Utilization rate too low"); // Minimum 50%
        uint256 oldValue = maxUtilizationOnWithdraw;
        maxUtilizationOnWithdraw = bps;
        emit MaxUtilizationOnWithdrawUpdated(oldValue, bps);
    }

    function setVaultHardcodedYield(uint256 yieldBPS) external onlyOwner {
        require(yieldBPS <= BASIS_POINTS, "Yield rate too high");
        uint256 oldValue = vaultHardcodedYield;
        vaultHardcodedYield = yieldBPS;
        emit VaultHardcodedYieldUpdated(oldValue, yieldBPS);
    }

    function setProtocolFeeRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), "Invalid address");
        protocolFeeRecipient = recipient;
    }

    function setVaultFeeRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), "Invalid address");
        vaultFeeRecipient = recipient;
    }

    function withdrawFees(uint256 amount, bool isProtocol) external onlyOwner {
        if (isProtocol) {
            require(
                amount <= accruedProtocolFees,
                "Insufficient protocol fees"
            );
            accruedProtocolFees -= amount;
            usdc.safeTransfer(protocolFeeRecipient, amount);
        } else {
            require(amount <= accruedVaultFees, "Insufficient vault fees");
            accruedVaultFees -= amount;
            usdc.safeTransfer(vaultFeeRecipient, amount);
        }
    }

    function recoverTokens(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        require(to != address(0), "Invalid recipient");

        IERC20 tokenContract = IERC20(token);
        uint256 balance = tokenContract.balanceOf(address(this));
        require(balance > 0, "No tokens to recover");

        if (amount == 0) amount = balance;
        else require(amount <= balance, "Insufficient token balance");

        tokenContract.safeTransfer(to, amount);
        emit TokensRecovered(token, to, amount);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    function version() external pure returns (string memory) {
        return "1.0.0";
    }
}
