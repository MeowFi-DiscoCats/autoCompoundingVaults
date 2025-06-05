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
import "./IMonadPriceFetcher.sol";

contract USDCBorrowingPoolV2 is
    Initializable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using Math for uint256;

    struct LenderInfo {
        uint256 depositAmount; // USDC deposited (6 decimals)
        uint256 lastUpdateTime; // Last interest calculation
        uint256 accruedInterest; // Interest earned (6 decimals)
    }

    struct BorrowerPosition {
        uint256 collateralAmount;
        uint256 borrowedAmount; // USDC borrowed (6 decimals)
        uint256 lastUpdateTime; // Last interest calculation
        uint256 accruedInterest; // Interest owed (6 decimals)
        bool isActive; // Position status
    }

    // Core contracts
    BubbleLPVault public bubbleVault;
    IERC20Upgradeable public usdc;
    IERC20Upgradeable public tokenA;
    IERC20Upgradeable public tokenB;
    IERC20Upgradeable public lpToken;
    IBubbleV1Router public bubbleRouter;
    IOctoswapRouter02 public octoRouter;
    IMonadPriceFetcher public priceFetcher;

    // Token addresses - immutable constants
    address public constant USDC_ADDRESS =
        0xf817257fed379853cDe0fa4F97AB987181B1E5Ea;
    address public constant WMON_ADDRESS =
        0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701;
    address public constant SHMON_ADDRESS =
        0x3a98250F98Dd388C211206983453837C8365BDc1;

    // Protocol parameters - can be updated by owner
    uint256 public liquidationThreshold; // 70% = 7000 basis points
    uint256 public maxLTV; // 65% = 6500 basis points
    uint256 public liquidationPenalty; // 5% = 500 basis points
    uint256 public annualInterestRate; // 10% = 1000 basis points
    uint256 public lenderShare; // 80% = 8000 basis points
    uint256 public slippageBPS; // 3% = 300 basis points
    uint256 public protocolFeeRate; // 20% = 2000 basis points (of interest)

    // Constants
    uint256 public constant LIQUIDATION_THRESHOLD = 7000; // 70%
    uint256 private constant USDC_DECIMALS = 6;
    uint256 private constant ORACLE_DECIMALS = 18; // Oracle returns 18 decimals
    uint256 private constant CALCULATION_DECIMALS = 18; // Internal calculations in 18 decimals
    uint256 private constant USDC_TO_CALC_SCALE = 1e12; // 10^(18-6) = 1e12
    uint256 private constant BASIS_POINTS = 10000;

    // State variables
    mapping(address => LenderInfo) public lenders;
    mapping(address => BorrowerPosition) public borrowers;

    address[] public activeBorrowers;
    mapping(address => uint256) public borrowerIndex; // borrower => index in activeBorrowers array

    uint256 public totalLent; // Total USDC lent (6 decimals)
    uint256 public totalBorrowed; // Total USDC borrowed (6 decimals)
    uint256 public totalCollateral; // Total vault shares as collateral
    uint256 public lastAccrualTime; // Last global interest accrual
    uint256 public accumulatedFees; // Protocol fees (6 decimals)

    address public gelatoAddress; // Address authorized to perform liquidations
    bool public liquidationEnabled = true;

    // Emergency controls
    bool public borrowingPaused;
    bool public liquidationsPaused;

    uint256 public counter = 1;

    //TO ADD AFTER THIS

    // Events
    event LentUSDC(address indexed lender, uint256 amount, uint256 timestamp);
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
    event TokensRecovered(
        address indexed token,
        address indexed to,
        uint256 amount
    );
    event ParametersUpdated(
        string parameter,
        uint256 oldValue,
        uint256 newValue
    );
    event EmergencyAction(string action, bool status);

    event GelatoAddressUpdated(
        address indexed oldAddress,
        address indexed newAddress
    );

    event CollateralDeposited(
        address indexed borrower,
        uint256 collateralAmount,
        uint256 timestamp
    );

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _bubbleVault,
        address _usdc,
        address _tokenA,
        address _tokenB,
        address _lpToken,
        IBubbleV1Router _bubbleRouter,
        IOctoswapRouter02 _octoRouter,
        address _priceFetcher,
        address _owner
    ) public initializer {
        require(_bubbleVault != address(0), "Invalid bubble vault");
        require(_usdc != address(0), "Invalid USDC");
        require(_tokenA != address(0), "Invalid tokenA");
        require(_tokenB != address(0), "Invalid tokenB");
        require(_lpToken != address(0), "Invalid LP token");
        require(address(_bubbleRouter) != address(0), "Invalid bubble router");
        require(address(_octoRouter) != address(0), "Invalid octo router");
        require(_priceFetcher != address(0), "Invalid price fetcher");
        require(_owner != address(0), "Invalid owner");

        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        bubbleVault = BubbleLPVault(_bubbleVault);
        usdc = IERC20Upgradeable(_usdc);
        tokenA = IERC20Upgradeable(_tokenA);
        tokenB = IERC20Upgradeable(_tokenB);
        lpToken = IERC20Upgradeable(_lpToken);
        bubbleRouter = IBubbleV1Router(_bubbleRouter);
        octoRouter = IOctoswapRouter02(_octoRouter);
        priceFetcher = IMonadPriceFetcher(_priceFetcher);

        liquidationThreshold = 7000; // 70%
        maxLTV = 6500; // 65%
        liquidationPenalty = 500; // 5%
        annualInterestRate = 1000; // 10%
        lenderShare = 8000; // 80%
        slippageBPS = 300; // 3%
        protocolFeeRate = 2000; // 20%

        lastAccrualTime = block.timestamp;
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

    function setGelatoAddress(address _gelatoAddress) external onlyOwner {
        address oldAddress = gelatoAddress;
        gelatoAddress = _gelatoAddress;
        emit GelatoAddressUpdated(oldAddress, _gelatoAddress);
    }

    function setLiquidationEnabled(bool _enabled) external onlyOwner {
        liquidationEnabled = _enabled;
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
    /// @param token Token address
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
        if (index == 0) return; // Not in array or first element already handled

        uint256 arrayIndex = index - 1; // Convert to 0-based indexing
        uint256 lastIndex = activeBorrowers.length - 1;

        if (arrayIndex != lastIndex) {
            address lastBorrower = activeBorrowers[lastIndex];
            activeBorrowers[arrayIndex] = lastBorrower;
            borrowerIndex[lastBorrower] = index;
        }

        activeBorrowers.pop();
        delete borrowerIndex[borrower];
    }

    ///  Lend USDC to the pool
    /// @param amount Amount (6 decimals) of USDC to lend
    function lendUSDC(uint256 amount)
        external
        nonReentrant
        whenNotPaused
        validAmount(amount)
    {
        _accrueInterest();

        LenderInfo storage lender = lenders[msg.sender];
        if (lender.depositAmount > 0) {
            _updateLenderInterest(msg.sender);
        }

        lender.depositAmount += amount;
        lender.lastUpdateTime = block.timestamp;
        totalLent += amount;

        usdc.safeTransferFrom(msg.sender, address(this), amount);
        emit LentUSDC(msg.sender, amount, block.timestamp);
    }

    ///  Withdraw lent USDC plus earned interest
    /// @param amount Amount to withdraw (0 = withdraw all)
    function withdrawUSDC(uint256 amount) external nonReentrant whenNotPaused {
        LenderInfo storage lender = lenders[msg.sender];
        require(lender.depositAmount > 0, "No deposit found");

        _accrueInterest();
        _updateLenderInterest(msg.sender);

        if (amount == 0) {
            amount = lender.depositAmount;
        }
        require(amount <= lender.depositAmount, "Insufficient deposit");

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

        lender.depositAmount -= amount;
        lender.accruedInterest -= interestToWithdraw;
        totalLent -= amount;

        usdc.safeTransfer(msg.sender, totalWithdraw);
        emit WithdrewUSDC(
            msg.sender,
            amount,
            interestToWithdraw,
            block.timestamp
        );
    }

    // Add this new function for depositing additional collateral
    function depositCollateral(uint256 collateralAmount)
        external
        nonReentrant
        whenNotPaused
        onlyActiveBorrower(msg.sender)
        validAmount(collateralAmount)
    {
        require(
            IERC20Upgradeable(address(bubbleVault)).balanceOf(msg.sender) >=
                collateralAmount,
            "Insufficient vault shares balance"
        );

        _accrueInterest();
        _updateBorrowerInterest(msg.sender);

        BorrowerPosition storage position = borrowers[msg.sender];

        IERC20Upgradeable(address(bubbleVault)).safeTransferFrom(
            msg.sender,
            address(this),
            collateralAmount
        );

        position.collateralAmount += collateralAmount;
        position.lastUpdateTime = block.timestamp;

        totalCollateral += collateralAmount;

        emit CollateralDeposited(msg.sender, collateralAmount, block.timestamp);
    }

    function borrow(uint256 collateralAmount, uint256 borrowAmount)
        external
        nonReentrant
        whenNotPaused
        notBorrowingPaused
        validAmount(borrowAmount) // Remove validAmount check for collateralAmount to allow 0
    {
        require(
            usdc.balanceOf(address(this)) >= borrowAmount,
            "Insufficient liquidity"
        );

        _accrueInterest();

        BorrowerPosition storage position = borrowers[msg.sender];

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
            maxLTV,
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
        totalCollateral += collateralAmount;
        totalBorrowed += borrowAmount;

        usdc.safeTransfer(msg.sender, borrowAmount);
        emit Borrowed(
            msg.sender,
            collateralAmount,
            borrowAmount,
            block.timestamp
        );
    }

    // Add this view function to check borrowing capacity
    function getBorrowingCapacity(address borrower)
        external
        view
        returns (
            uint256 maxBorrow,
            uint256 currentDebt,
            uint256 availableToBorrow
        )
    {
        BorrowerPosition storage position = borrowers[borrower];

        if (!position.isActive) {
            return (0, 0, 0);
        }

        uint256 collateralValueUSDC = _getCollateralValue(
            position.collateralAmount
        );
        maxBorrow = collateralValueUSDC.mulDiv(
            maxLTV,
            BASIS_POINTS,
            Math.Rounding.Floor
        );
        currentDebt =
            position.borrowedAmount +
            _calculateBorrowerInterest(borrower);
        availableToBorrow = maxBorrow > currentDebt
            ? maxBorrow - currentDebt
            : 0;
    }

    ///  Repay borrowed USDC
    /// @param repayAmount Amount to repay
    function repay(uint256 repayAmount)
        external
        nonReentrant
        whenNotPaused
        onlyActiveBorrower(msg.sender)
        validAmount(repayAmount)
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

        // Update position
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
            totalCollateral -= collateralToReturn;
            _removeActiveBorrower(msg.sender);
        }

        // Update pool state
        totalBorrowed -= principalPaid;

        // Protocol fee
        uint256 protocolFee = interestPaid.mulDiv(
            protocolFeeRate,
            BASIS_POINTS,
            Math.Rounding.Floor
        );
        accumulatedFees += protocolFee;

        // Return collateral if fully repaid
        if (collateralToReturn > 0) {
            IERC20Upgradeable(address(bubbleVault)).safeTransfer(
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

    ///  Check if position is healthy
    function _isHealthy(address borrower, bool forLiquidation)
        internal
        view
        returns (bool)
    {
        BorrowerPosition storage position = borrowers[borrower];
        if (!position.isActive || position.collateralAmount == 0) return true;

        // (6 decimals)
        uint256 collateralValueUSDC = _getCollateralValue(
            position.collateralAmount
        );

        //  (6 decimals)
        uint256 totalDebtUSDC = position.borrowedAmount +
            _calculateBorrowerInterest(borrower);

        if (totalDebtUSDC == 0) return true;

        uint256 threshold = forLiquidation ? liquidationThreshold : maxLTV;

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
    function liquidate(address borrower)
        external
        nonReentrant
        whenNotPaused
        notLiquidationsPaused
        onlyActiveBorrower(borrower)
    {
        require(liquidationEnabled, "Liquidation is disabled");
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
            liquidationPenalty,
            BASIS_POINTS,
            Math.Rounding.Floor
        );
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
        totalBorrowed -= principalRepaid;
        totalCollateral -= collateralToLiquidate;

        // Protocol fee from interest
        uint256 protocolFee = interestRepaid.mulDiv(
            protocolFeeRate,
            BASIS_POINTS,
            Math.Rounding.Floor
        );
        accumulatedFees += protocolFee;

        // Transfer penalty to site
        if (penalty > 0) {
            usdc.safeTransfer(msg.sender, penalty);
        }

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

    function liquidateMultiple(address[] calldata borrowersToLiquidate)
        external
        nonReentrant
    {
        require(liquidationEnabled, "Liquidation is disabled");
        require(borrowersToLiquidate.length > 0, "No borrowers provided");
        require(
            borrowersToLiquidate.length <= 10,
            "Too many borrowers at once"
        );

        for (uint256 i = 0; i < borrowersToLiquidate.length; i++) {
            address borrower = borrowersToLiquidate[i];
            BorrowerPosition storage position = borrowers[borrower];

            if (!position.isActive) continue;
            _updateBorrowerInterest(borrower);
            if (_isHealthy(borrower, true)) continue;

            uint256 totalDebt = position.borrowedAmount +
                position.accruedInterest;
            uint256 collateralToLiquidate = position.collateralAmount;

            uint256 usdcRecovered = _liquidateCollateral(collateralToLiquidate);
            if (usdcRecovered == 0) continue;

            uint256 penalty = usdcRecovered.mulDiv(
                liquidationPenalty,
                BASIS_POINTS,
                Math.Rounding.Floor
            );
            uint256 availableForDebt = usdcRecovered - penalty;
            uint256 debtRepayment = Math.min(totalDebt, availableForDebt);

            uint256 principalRepaid = Math.min(
                debtRepayment,
                position.borrowedAmount
            );
            uint256 interestRepaid = debtRepayment - principalRepaid;

            position.borrowedAmount -= principalRepaid;
            position.accruedInterest -= interestRepaid;
            position.collateralAmount = 0;
            position.isActive = false;

            _removeActiveBorrower(borrower);

            totalBorrowed -= principalRepaid;
            totalCollateral -= collateralToLiquidate;

            uint256 protocolFee = interestRepaid.mulDiv(
                2000,
                BASIS_POINTS,
                Math.Rounding.Floor
            );
            accumulatedFees += protocolFee;

            // Keep any excess as protocol revenue

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
    }

    /// Convert vault shares to USDC through liquidation
    function _liquidateCollateral(uint256 vaultShares)
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
            BASIS_POINTS - slippageBPS,
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
    function _calculateBorrowerInterest(address borrower)
        internal
        view
        returns (uint256)
    {
        BorrowerPosition storage position = borrowers[borrower];
        if (!position.isActive || position.borrowedAmount == 0)
            return position.accruedInterest;

        uint256 timeElapsed = block.timestamp - position.lastUpdateTime;
        uint256 newInterest = position.borrowedAmount.mulDiv(
            annualInterestRate * timeElapsed,
            BASIS_POINTS * 365 days,
            Math.Rounding.Ceil
        );

        return position.accruedInterest + newInterest;
    }

    /// Calculate lender interest
    function _calculateLenderInterest(address lender)
        internal
        view
        returns (uint256)
    {
        LenderInfo storage info = lenders[lender];
        if (info.depositAmount == 0) return info.accruedInterest;

        uint256 timeElapsed = block.timestamp - info.lastUpdateTime;
        uint256 utilization = totalLent > 0
            ? totalBorrowed.mulDiv(BASIS_POINTS, totalLent, Math.Rounding.Floor)
            : 0;
        uint256 lenderRate = annualInterestRate
            .mulDiv(utilization, BASIS_POINTS, Math.Rounding.Floor)
            .mulDiv(lenderShare, BASIS_POINTS, Math.Rounding.Floor);

        uint256 newInterest = info.depositAmount.mulDiv(
            lenderRate * timeElapsed,
            BASIS_POINTS * 365 days,
            Math.Rounding.Floor
        );

        return info.accruedInterest + newInterest;
    }

    /// Update borrower interest
    function _updateBorrowerInterest(address borrower) internal {
        BorrowerPosition storage position = borrowers[borrower];
        position.accruedInterest = _calculateBorrowerInterest(borrower);
        position.lastUpdateTime = block.timestamp;
    }

    /// Update lender interest
    function _updateLenderInterest(address lender) internal {
        LenderInfo storage info = lenders[lender];
        info.accruedInterest = _calculateLenderInterest(lender);
        info.lastUpdateTime = block.timestamp;
    }

    /// Accrue global interest
    function _accrueInterest() internal {
        lastAccrualTime = block.timestamp;
    }

    // VIEW FUNCTIONS

    ///  Get borrower position with current interest
    function getBorrowerPosition(address borrower)
        external
        view
        returns (BorrowerPosition memory position)
    {
        position = borrowers[borrower];
        position.accruedInterest = _calculateBorrowerInterest(borrower);
    }

    ///  Get lender info with current interest
    function getLenderInfo(address lender)
        external
        view
        returns (LenderInfo memory info)
    {
        info = lenders[lender];
        info.accruedInterest = _calculateLenderInterest(lender);
    }

    ///  Check if position can be liquidated
    function canLiquidate(address borrower) external view returns (bool) {
        BorrowerPosition storage position = borrowers[borrower];
        if (!position.isActive) return false;
        return !_isHealthy(borrower, true);
    }

    ///  Get health factor
    function getHealthFactor(address borrower) external view returns (uint256) {
        BorrowerPosition storage position = borrowers[borrower];
        if (!position.isActive) return type(uint256).max;

        uint256 collateralValueUSDC = _getCollateralValue(
            position.collateralAmount
        );
        uint256 totalDebtUSDC = position.borrowedAmount +
            _calculateBorrowerInterest(borrower);

        if (totalDebtUSDC == 0) return type(uint256).max;

        return
            collateralValueUSDC.mulDiv(
                liquidationThreshold,
                totalDebtUSDC,
                Math.Rounding.Floor
            );
    }

    ///  Get collateral value in USDC (6 decimals for display)
    function getCollateralValueInUSDC(uint256 vaultShares)
        external
        view
        returns (uint256)
    {
        return _getCollateralValue(vaultShares);
    }

    ///  Get current token price in USDC (6 decimals for display)
    function getTokenPrice(address token) external view returns (uint256) {
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
    function getUnderlyingTokens(uint256 vaultShares)
        external
        view
        returns (uint256 tokenAAmount, uint256 tokenBAmount)
    {
        if (vaultShares == 0) return (0, 0);
        uint256 lpTokenAmount = bubbleVault.previewRedeem(vaultShares);
        return _calculateTokenAmountsFromLP(lpTokenAmount);
    }

    ///  Withdraw protocol fees
    function withdrawFees(uint256 amount) external onlyOwner {
        require(amount <= accumulatedFees, "Insufficient fees");
        accumulatedFees -= amount;
        usdc.safeTransfer(msg.sender, amount);
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

    function checker()
        external
        view
        returns (bool canExec, bytes memory execPayload)
    {
        // Get liquidatable positions (max 5 for gas efficiency)
        address[] memory liquidatablePositions = getLiquidatablePositions(5);

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

    function checkerSingle()
        external
        view
        returns (bool canExec, bytes memory execPayload)
    {
        address liquidatablePosition = getFirstLiquidatablePosition();

        if (liquidatablePosition != address(0)) {
            execPayload = abi.encodeWithSelector(
                this.liquidate.selector,
                liquidatablePosition
            );
            canExec = true;
        } else {
            canExec = false;
            execPayload = bytes("");
        }
    }

    function getLiquidatablePositions(uint256 maxPositions)
        public
        view
        returns (address[] memory liquidatable)
    {
        if (!liquidationEnabled || activeBorrowers.length == 0) {
            return new address[](0);
        }

        address[] memory temp = new address[](maxPositions);
        uint256 count = 0;

        for (
            uint256 i = 0;
            i < activeBorrowers.length && count < maxPositions;
            i++
        ) {
            address borrower = activeBorrowers[i];
            BorrowerPosition storage position = borrowers[borrower];

            if (position.isActive && !_isHealthy(borrower, true)) {
                temp[count] = borrower;
                count++;
            }
        }

        liquidatable = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            liquidatable[i] = temp[i];
        }
    }

    /// @notice Get first liquidatable position (for single liquidation strategy)
    /// @return borrower Address of first liquidatable borrower, or address(0) if none
    function getFirstLiquidatablePosition()
        public
        view
        returns (address borrower)
    {
        if (!liquidationEnabled || activeBorrowers.length == 0) {
            return address(0);
        }

        for (uint256 i = 0; i < activeBorrowers.length; i++) {
            address currentBorrower = activeBorrowers[i];
            BorrowerPosition storage position = borrowers[currentBorrower];

            if (position.isActive && !_isHealthy(currentBorrower, true)) {
                return currentBorrower;
            }
        }

        return address(0);
    }

    function getLiquidatableCount() external view returns (uint256 count) {
        if (!liquidationEnabled) return 0;

        for (uint256 i = 0; i < activeBorrowers.length; i++) {
            address borrower = activeBorrowers[i];
            BorrowerPosition storage position = borrowers[borrower];

            if (position.isActive && !_isHealthy(borrower, true)) {
                count++;
            }
        }
    }

    function liquidationsNeeded() external view returns (bool needed) {
        if (!liquidationEnabled || activeBorrowers.length == 0) {
            return false;
        }

        uint256 checkLimit = activeBorrowers.length > 10
            ? 10
            : activeBorrowers.length;

        for (uint256 i = 0; i < checkLimit; i++) {
            address borrower = activeBorrowers[i];
            BorrowerPosition storage position = borrowers[borrower];

            if (position.isActive && !_isHealthy(borrower, true)) {
                return true;
            }
        }

        return false;
    }

    fallback() external {}
}
