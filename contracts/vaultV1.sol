// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./bubbleFiABI.sol";
import "./uniswaphelper.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title BubbleLPVault
/// @notice ERC4626 vault for Bubble LP tokens, with profit-only redemption fee and configurable slippage
contract BubbleLPVault is ERC4626, Ownable, ReentrancyGuard {
    using Math for uint256;

    // Underlying tokens
    ERC20 public immutable tokenA;
    ERC20 public immutable tokenB;
    IBubbleV1Router public immutable bubbleRouter;
    ERC20 public immutable lpToken;

    // Fee on profit, in basis points (e.g. 100 = 1%)
    uint16 public feeBps;
    address public feeRecipient;
    uint256[] public apyFeeReceived;

    // Fee on deposit (bps, e.g. 59 = 0.59%)
    uint16 public depositFeeBps;
    address public depositFeeRecipient;
    uint256[] public depositFeeReceived;

    // Slippage tolerance, in basis points (e.g. 100 = 1%) applied to all adds/removes
    uint16 public slippageBps;
  ///meowfi -> bubblfi -> bubblei pool
    // Tracks deposited LP token principal per user
    mapping(address => uint256) private userPrincipal;
    IOctoswapRouter02 public immutable octoRouter;

    event Compounded(uint256 lpTokensAdded, uint256 newTotalAssets);
    event FeeTaken(address indexed user, uint256 feeA, uint256 feeB);
    event SlippageUpdated(uint16 oldSlippage, uint16 newSlippage);
    event FeeParamsUpdated(
        uint16 oldFeeBps,
        uint16 newFeeBps,
        address indexed newRecipient
    );
    event rawDeposit(address indexed user, uint256 grossLp, uint256 netLp);

    constructor(
        ERC20 _tokenA,
        ERC20 _tokenB,
        IBubbleV1Router _bubbleRouter,
        ERC20 _lpToken,
        uint16 _feeBps,
        address _feeRecipient,
        uint16 _depositFeeBps,
        uint16 _slippageBps,
        IOctoswapRouter02 _octoRouter
    )
        ERC4626(_lpToken)
        Ownable(msg.sender)
        ERC20("MeowFi LP Vault", "MLP-VAULT")
    {
        tokenA = _tokenA;
        tokenB = _tokenB;
        bubbleRouter = _bubbleRouter;
        lpToken = _lpToken;
        feeBps = _feeBps;
        feeRecipient = _feeRecipient;
        slippageBps = _slippageBps;
        octoRouter = _octoRouter;
        depositFeeBps = _depositFeeBps;
        depositFeeRecipient = _feeRecipient;
        apyFeeReceived = new uint256[](2);
        depositFeeReceived = new uint256[](2);
    }

    /// @notice Update slippage tolerance (bps)
    function setSlippageBps(uint16 _newSlippageBps) external onlyOwner {
        require(_newSlippageBps <= 1000, "Max 10% slippage");
        emit SlippageUpdated(slippageBps, _newSlippageBps);
        slippageBps = _newSlippageBps;
    }

    function setDepositFeeParams(
        uint16 _newDepositFeeBps,
        address _newRecipient
    ) external onlyOwner {
        require(_newDepositFeeBps <= 1000, "Max 10% fee");
        depositFeeBps = _newDepositFeeBps;
        depositFeeRecipient = _newRecipient;
    }

    /// @notice Update fee params
    function setFeeParams(uint16 _newFeeBps, address _newRecipient)
        external
        onlyOwner
    {
        require(_newFeeBps <= 1000, "Max 10% fee");
        emit FeeParamsUpdated(feeBps, _newFeeBps, _newRecipient);
        feeBps = _newFeeBps;
        feeRecipient = _newRecipient;
    }

    //
    //-------------------------join single--------------------------//
    //
    function joinSingle(
        uint256 amountIn,
        address inputToken,
        address receiver
    ) external nonReentrant returns (uint256 shares) {
        require(
            inputToken == address(tokenA) || inputToken == address(tokenB),
            "Unsupported"
        );

        IERC20(inputToken).transferFrom(msg.sender, address(this), amountIn);
        
        uint256 fee = amountIn.mulDiv(
            depositFeeBps,
            10_000,
            Math.Rounding.Floor
        );
        uint256 amountAfterFee = amountIn - fee;

        // Transfer fee to recipient
        IERC20(inputToken).transfer(depositFeeRecipient, fee);
        if(inputToken == address(tokenA) ){
            depositFeeReceived[0]+=amountAfterFee;
        }else if(inputToken == address(tokenB)){
            depositFeeReceived[1]+=amountAfterFee;
        }

        // Transfer remaining amount to contract
        // IERC20(inputToken).transferFrom(
        //     msg.sender,
        //     address(this),
        //     amountAfterFee
        // );

        uint256 half = amountAfterFee / 2;
        uint256 otherHalf = amountAfterFee - half;

        uint256 swapped = _swapHalf(inputToken, half);

        // now assemble for addLiquidity…
        (uint256 amtA, uint256 amtB) = inputToken == address(tokenA)
            ? (otherHalf, swapped)
            : (swapped, otherHalf);

        // approve & add
        tokenA.approve(address(bubbleRouter), amtA);
        tokenB.approve(address(bubbleRouter), amtB);
        (, , uint256 lpReceived) = _addLiquidity(
            amtA,
            amtB,
            amtA.mulDiv(10_000 - slippageBps, 10_000, Math.Rounding.Floor),
            amtB.mulDiv(10_000 - slippageBps, 10_000, Math.Rounding.Floor)
        );

        shares = previewDeposit(lpReceived);
        _mint(receiver, shares);

        userPrincipal[receiver] += lpReceived;

        emit Deposit(msg.sender, receiver, lpReceived, shares);
        // emit rawDeposit(msg.sender,lpReceived, netLp);
    }

    // function _applyDepositFee(uint256 grossLp)
    //     internal
    //     returns (uint256 netLp)
    // {
    //     // compute net and send fee out
    //     netLp = grossLp.mulDiv(
    //         10_000 - depositFeeBps,
    //         10_000,
    //         Math.Rounding.Floor
    //     );
    //     lpToken.transfer(depositFeeRecipient, grossLp - netLp);
    //     depositFeeReceived += (grossLp - netLp);
    // }

    function _swapHalf(address inputToken, uint256 half)
        internal
        returns (uint256 swapped)
    {
        // build path, approve, getAmountsOut, swap...
        address[] memory path = new address[](2);

        // build path to the other token address;
        if (inputToken == address(tokenA)) {
            path[0] = address(tokenA);
            path[1] = address(tokenB);
        } else {
            path[0] = address(tokenB);
            path[1] = address(tokenA);
        }

        // approve & compute slippage‐guarded minOut
        IERC20(inputToken).approve(address(octoRouter), half);
        uint256[] memory amountsOut = octoRouter.getAmountsOut(half, path);
        uint256 minOut = amountsOut[amountsOut.length - 1].mulDiv(
            10_000 - slippageBps,
            10_000,
            Math.Rounding.Floor
        );

        // do the swap
        uint256[] memory swappedAmounts = octoRouter.swapExactTokensForTokens(
            half,
            minOut,
            path,
            address(this),
            block.timestamp + 300
        );
        return swapped = swappedAmounts[swappedAmounts.length - 1];
    }

    /// --------------reclaim----------
    //Burn shares, remove liquidity (with slippage), charge fee on profit, and transfer underlyings

    function reclaim(
        uint256 shares,
        address receiver,
        address owner
    ) public nonReentrant returns (uint256 amountA, uint256 amountB) {
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        uint256 supplyBefore = totalSupply();
        uint256 lpToRedeem = previewRedeem(shares);

        uint256 principalShare = (userPrincipal[owner] * shares) / supplyBefore;
        userPrincipal[owner] -= principalShare;

        // profit only on LP tokens
        uint256 profitLp = lpToRedeem > principalShare
            ? lpToRedeem - principalShare
            : 0;
        uint256 feeLp = profitLp.mulDiv(feeBps, 10_000, Math.Rounding.Floor);
        uint256 netLp = lpToRedeem - feeLp;

        _burn(owner, shares);

        // compute slippage-guarded minimums for net redemption
        (uint256 expA, uint256 expB) = _getExpectedTokens(netLp);
        uint256 minA = expA.mulDiv(
            10_000 - slippageBps,
            10_000,
            Math.Rounding.Floor
        );
        uint256 minB = expB.mulDiv(
            10_000 - slippageBps,
            10_000,
            Math.Rounding.Floor
        );

        lpToken.approve(address(bubbleRouter), netLp);
        (amountA, amountB) = bubbleRouter.removeLiquidity(
            address(tokenA),
            address(tokenB),
            netLp,
            minA,
            minB,
            address(this),
            block.timestamp + 1200
        );

        // handle fee portion
        if (feeLp > 0) {
            (uint256 feeA, uint256 feeB) = _removeWithSlippage(feeLp);
            tokenA.transfer(feeRecipient, feeA);
            tokenB.transfer(feeRecipient, feeB);
            apyFeeReceived[0] += feeA;
            apyFeeReceived[1] += feeB;

            emit FeeTaken(owner, feeA, feeB);
        }

        tokenA.transfer(receiver, amountA);
        tokenB.transfer(receiver, amountB);

        // emit Withdraw(msg.sender, receiver, owner, lpToRedeem, shares);
    }

    /// @dev Internal removeLiquidity with slippage guard
    function _removeWithSlippage(uint256 lpAmount)
        internal
        returns (uint256 outA, uint256 outB)
    {
        lpToken.approve(address(bubbleRouter), lpAmount);
        (uint256 expA, uint256 expB) = _getExpectedTokens(lpAmount);
        uint256 minA = expA.mulDiv(
            10_000 - slippageBps,
            10_000,
            Math.Rounding.Floor
        );
        uint256 minB = expB.mulDiv(
            10_000 - slippageBps,
            10_000,
            Math.Rounding.Floor
        );
        return
            bubbleRouter.removeLiquidity(
                address(tokenA),
                address(tokenB),
                lpAmount,
                minA,
                minB,
                address(this),
                block.timestamp + 1200
            );
    }

    //-----------------autocompound------------------
    /// @notice Auto-compound LP tokens, respecting slippage

    function autocompound() external nonReentrant {
        uint256 lpBalance = lpToken.balanceOf(address(this));
        if (lpBalance == 0) return;

        (uint256 expA, uint256 expB) = _getExpectedTokens(lpBalance);
        uint256 minA = expA.mulDiv(
            10_000 - slippageBps,
            10_000,
            Math.Rounding.Floor
        );
        uint256 minB = expB.mulDiv(
            10_000 - slippageBps,
            10_000,
            Math.Rounding.Floor
        );

        lpToken.approve(address(bubbleRouter), lpBalance);
        (uint256 receivedA, uint256 receivedB) = bubbleRouter.removeLiquidity(
            address(tokenA),
            address(tokenB),
            lpBalance,
            minA,
            minB,
            address(this),
            block.timestamp + 1200
        );

        (, , uint256 newLpTokens) = _addLiquidity(
            receivedA,
            receivedB,
            receivedA.mulDiv(10_000 - slippageBps, 10_000, Math.Rounding.Floor),
            receivedB.mulDiv(10_000 - slippageBps, 10_000, Math.Rounding.Floor)
        );

        uint256 minLpTokens = lpBalance.mulDiv(10_000 - slippageBps, 10_000, Math.Rounding.Floor);
        require(newLpTokens >= minLpTokens, "Slippage too high");
        emit Compounded(newLpTokens, totalAssets());
    }

    // unchanged helpers and overrides...
    function _getExpectedTokens(uint256 lpAmount)
        internal
        view
        returns (uint256 expectedA, uint256 expectedB)
    {
        uint256 totalSup = lpToken.totalSupply();
        uint256 resA = tokenA.balanceOf(address(lpToken));
        uint256 resB = tokenB.balanceOf(address(lpToken));
        expectedA = (lpAmount * resA) / totalSup;
        expectedB = (lpAmount * resB) / totalSup;
    }

    function _addLiquidity(
        uint256 amountA,
        uint256 amountB,
        uint256 minA,
        uint256 minB
    )
        internal
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        tokenA.approve(address(bubbleRouter), amountA);
        tokenB.approve(address(bubbleRouter), amountB);
        return
            bubbleRouter.addLiquidity(
                BubbleV1Types.AddLiquidity({
                    tokenA: address(tokenA),
                    tokenB: address(tokenB),
                    amountADesired: amountA,
                    amountBDesired: amountB,
                    amountAMin: minA,
                    amountBMin: minB,
                    receiver: address(this),
                    deadline: block.timestamp + 1200
                })
            );
    }

    function totalAssets() public view override returns (uint256) {
        return lpToken.balanceOf(address(this));
    }

    function previewRedeem(uint256 shares)
        public
        view
        override
        returns (uint256)
    {
        return shares.mulDiv(totalAssets(), totalSupply(), Math.Rounding.Floor);
    }

    function previewDeposit(uint256 assets)
        public
        view
        override
        returns (uint256)
    {
        uint256 supply = totalSupply();
        return
            supply == 0
                ? assets
                : assets.mulDiv(supply, totalAssets(), Math.Rounding.Floor);
    }
}
