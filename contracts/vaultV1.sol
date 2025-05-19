// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./bubble.sol";

contract BubbleLPVault is ERC4626 {
    using Math for uint256;

    // Tokens accepted for LP (e.g., USDC/WETH)
    ERC20 public immutable tokenA;
    ERC20 public immutable tokenB;

    // Bubble Router for adding/removing liquidity
    IBubbleV1Router public immutable bubbleRouter;

    // Bubble LP Token (received when adding liquidity)
    ERC20 public immutable lpToken;

    ////events////
    event Compounded(uint256 lpTokensAdded, uint256 newTotalAssets);

    constructor(
        ERC20 _tokenA,
        ERC20 _tokenB,
        IBubbleV1Router _bubbleRouter,
        ERC20 _lpToken
    ) ERC4626(_lpToken) ERC20("Bubble LP Vault", "BLP-VAULT") {
        tokenA = _tokenA;
        tokenB = _tokenB;
        bubbleRouter = _bubbleRouter;
        lpToken = _lpToken;
    }

    
    //////// DEPOSIT (Join Pool + Mint Shares) /////
    

    /// @notice Deposit TokenA + TokenB, add liquidity to Bubble, and mint shares.
    function join(
        uint256 amountA,
        uint256 amountB,
        uint256 minLpTokens, // Minimum LP tokens to receive (slippage protection)
        address receiver
    ) external returns (uint256 shares) {
        require(amountA > 0 && amountB > 0, "Must deposit both tokens");

        // 1. Transfer tokens from user
        tokenA.transferFrom(msg.sender, address(this), amountA);
        tokenB.transferFrom(msg.sender, address(this), amountB);

        // 2. Approve Bubble Router to spend tokens
        tokenA.approve(address(bubbleRouter), amountA);
        tokenB.approve(address(bubbleRouter), amountB);

        // 3. Add liquidity to Bubble pool
        (uint256 usedA, uint256 usedB, uint256 lpReceived) = bubbleRouter.addLiquidity(
            BubbleV1Types.AddLiquidity({
                tokenA: address(tokenA),
                tokenB: address(tokenB),
                amountADesired: amountA,
                amountBDesired: amountB,
                amountAMin: amountA.mulDiv(95, 100), // 5% slippage tolerance
                amountBMin: amountB.mulDiv(95, 100),
                receiver: address(this),
                deadline: block.timestamp + 1200
            })
        );

        require(lpReceived >= minLpTokens, "Insufficient LP tokens received");

        // 4. Mint shares proportional to LP tokens received
        shares = previewDeposit(lpReceived);
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, lpReceived, shares);
    }

    
    //////// REDEEM (Burn Shares + Remove Liquidity) /////
    

    /// @notice Burn shares, remove liquidity from Bubble, and return TokenA + TokenB.
    function redeem(
        uint256 shares,
        uint256 minAmountA, // Minimum TokenA to receive (slippage protection)
        uint256 minAmountB, // Minimum TokenB to receive
        address receiver,
        address owner
    ) external returns (uint256 amountA, uint256 amountB) {
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        // 1. Calculate LP tokens to burn
        uint256 lpToBurn = previewRedeem(shares);
        _burn(owner, shares);

        // 2. Approve Bubble Router to burn LP tokens
        lpToken.approve(address(bubbleRouter), lpToBurn);

        // 3. Remove liquidity from Bubble pool
        (amountA, amountB) = bubbleRouter.removeLiquidity(
            address(tokenA),
            address(tokenB),
            lpToBurn,
            minAmountA,
            minAmountB,
            receiver,
            block.timestamp + 1200
        );

        emit Withdraw(msg.sender, receiver, owner, lpToBurn, shares);
    }


    ///////autocompound//////
    function autocompound(uint256 minLpTokens) external {
    
    uint256 lpBalance = lpToken.balanceOf(address(this));
    if (lpBalance == 0) return;

    // 1. CALCULATE EXPECTED TOKENS (The Right Way)
    (uint256 expectedA, uint256 expectedB) = _getExpectedTokens(lpBalance);
    
    // 2. REMOVE LIQUIDITY (With 1% Slippage Protection)
    _safeApprove(lpToken, address(bubbleRouter), lpBalance);
    (uint256 receivedA, uint256 receivedB) = bubbleRouter.removeLiquidity(
        address(tokenA),
        address(tokenB),
        lpBalance,
        expectedA.mulDiv(99, 100), // Minimum 99% of expected TokenA
        expectedB.mulDiv(99, 100), // Minimum 99% of expected TokenB
        address(this),
        block.timestamp + 1200
    );

    // 3. REINVEST (With 1% Slippage Protection)
    (,, uint256 newLpTokens) = _addLiquidity(
        receivedA, 
        receivedB,
        receivedA.mulDiv(99, 100),
        receivedB.mulDiv(99, 100)
    );
    
    require(newLpTokens >= minLpTokens, "Slippage too high");
    
    emit Compounded(newLpTokens, totalAssets());
}

function _getExpectedTokens(uint256 lpAmount) internal view returns (uint256 expectedA, uint256 expectedB) {
    // PROPORTIONAL REDEMPTION FORMULA:
    // Your Share = (Your LP Tokens) / (Total LP Supply)
    // Your TokenA = Your Share × Pool's TokenA Balance
    // Your TokenB = Your Share × Pool's TokenB Balance
    
    uint256 totalSupply = lpToken.totalSupply();
    uint256 reserveA = tokenA.balanceOf(address(lpToken));
    uint256 reserveB = tokenB.balanceOf(address(lpToken));
    
    expectedA = (lpAmount * reserveA) / totalSupply;
    expectedB = (lpAmount * reserveB) / totalSupply;
}

function _addLiquidity(
    uint256 amountA,
    uint256 amountB,
    uint256 minA,
    uint256 minB
) internal returns (uint256, uint256, uint256) {
    _safeApprove(tokenA, address(bubbleRouter), amountA);
    _safeApprove(tokenB, address(bubbleRouter), amountB);
    
    return bubbleRouter.addLiquidity(
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


    
    //////// INTERNAL HELPERS /////////////////////
    

    function _safeApprove(ERC20 token, address spender, uint256 amount) internal {
        if (token.allowance(address(this), spender) > 0) {
            token.approve(spender, 0);
        }
        token.approve(spender, amount);
    }

    
    //////// ERC-4626 OVERRIDES //////////////////
    

    /// @dev Total assets = LP tokens held by the vault.
    function totalAssets() public view override returns (uint256) {
        return lpToken.balanceOf(address(this));
    }

    /// @dev Convert shares to LP tokens.
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        return shares.mulDiv(totalAssets(), totalSupply(), Math.Rounding.Floor);
    }

    /// @dev Convert LP tokens to shares.
    function previewDeposit(uint256 assets) public view override returns (uint256) {
        uint256 supply = totalSupply();
        return (supply == 0) ? assets : assets.mulDiv(supply, totalAssets(), Math.Rounding.Floor);
    }
}