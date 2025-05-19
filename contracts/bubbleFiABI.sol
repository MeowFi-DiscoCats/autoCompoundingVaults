// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IBubbleV1Router {
    ///////////////////////
    /// Errors ///
    ///////////////////////

    error BubbleV1Router__DeadlinePasssed(uint256 givenDeadline, uint256 currentTimestamp);
    error BubbleV1Router__TransferFailed();
    error BubbleV1Router__PermitFailed();
    error BubbleV1Router__InsufficientAAmount(uint256 amountA, uint256 amountAMin);
    error BubbleV1Router__InsufficientBAmount(uint256 amountB, uint256 amountBMin);
    error BubbleV1Router__InsufficientOutputAmount(uint256 amountOut, uint256 amountOutMin);
    error BubbleV1Router__ExcessiveInputAmount(uint256 amountIn, uint256 amountInMax);
    error BubbleV1Router__InvalidPath();
    error BubbleV1Router__TokenNotSupportedByRaffle();

    //////////////////////////
    /// External Functions ///
    //////////////////////////

    receive() external payable;

    function addLiquidity(
        BubbleV1Types.AddLiquidity calldata _addLiquidityParams
    ) external returns (uint256, uint256, uint256);

    function addLiquidityNative(
        BubbleV1Types.AddLiquidityNative calldata _addLiquidityNativeParams
    ) external payable returns (uint256, uint256, uint256);

    function removeLiquidityWithPermit(
        BubbleV1Types.RemoveLiquidityWithPermit calldata _params
    ) external returns (uint256, uint256);

    function removeLiquidityNativeWithPermit(
        BubbleV1Types.RemoveLiquidityNativeWithPermit calldata _params
    ) external returns (uint256, uint256);

    function removeLiquidityNativeSupportingFeeOnTransferTokens(
        address _token,
        uint256 _lpTokensToBurn,
        uint256 _amountTokenMin,
        uint256 _amountNativeMin,
        address _receiver,
        uint256 _deadline
    ) external returns (uint256);

    function removeLiquidityNativeWithPermitSupportingFeeOnTransferTokens(
        address _token,
        uint256 _lpTokensToBurn,
        uint256 _amountTokenMin,
        uint256 _amountNativeMin,
        address _receiver,
        uint256 _deadline,
        bool _approveMax,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external returns (uint256);

    function swapExactTokensForTokens(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address[] calldata _path,
        address _receiver,
        uint256 _deadline,
        BubbleV1Types.Raffle memory _raffle
    ) external returns (uint256[] memory, uint256);

    function swapTokensForExactTokens(
        uint256 _amountOut,
        uint256 _amountInMax,
        address[] calldata _path,
        address _receiver,
        uint256 _deadline,
        BubbleV1Types.Raffle memory _raffle
    ) external returns (uint256[] memory, uint256);

    function swapExactNativeForTokens(
        uint256 _amountOutMin,
        address[] calldata _path,
        address _receiver,
        uint256 _deadline,
        BubbleV1Types.Raffle memory _raffle
    ) external payable returns (uint256[] memory, uint256);

    function swapTokensForExactNative(
        uint256 _amountOut,
        uint256 _amountInMax,
        address[] calldata _path,
        address _receiver,
        uint256 _deadline,
        BubbleV1Types.Raffle memory _raffle
    ) external returns (uint256[] memory, uint256);

    function swapExactTokensForNative(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address[] calldata _path,
        address _receiver,
        uint256 _deadline,
        BubbleV1Types.Raffle memory _raffle
    ) external returns (uint256[] memory, uint256);

    function swapNativeForExactTokens(
        uint256 _amountOut,
        address[] calldata _path,
        address _receiver,
        uint256 _deadline,
        BubbleV1Types.Raffle memory _raffle
    ) external payable returns (uint256[] memory, uint256);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address[] calldata _path,
        address _receiver,
        uint256 _deadline,
        BubbleV1Types.Raffle memory _raffle
    ) external;

    function swapExactNativeForTokensSupportingFeeOnTransferTokens(
        uint256 _amountOutMin,
        address[] calldata _path,
        address _receiver,
        uint256 _deadline,
        BubbleV1Types.Raffle memory _raffle
    ) external payable;

    function swapExactTokensForNativeSupportingFeeOnTransferTokens(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address[] calldata _path,
        address _receiver,
        uint256 _deadline,
        BubbleV1Types.Raffle memory _raffle
    ) external;

    ////////////////////////
    /// Public Functions ///
    ////////////////////////

    function removeLiquidity(
        address _tokenA,
        address _tokenB,
        uint256 _lpTokensToBurn,
        uint256 _amountAMin,
        uint256 _amountBMin,
        address _receiver,
        uint256 _deadline
    ) external returns (uint256, uint256);

    function removeLiquidityNative(
        address _token,
        uint256 _lpTokensToBurn,
        uint256 _amountTokenMin,
        uint256 _amountNativeMin,
        address _receiver,
        uint256 _deadline
    ) external returns (uint256, uint256);

    ///////////////////////////////
    /// View and Pure Functions ///
    ///////////////////////////////

    function getFactory() external view returns (address);
    function getRaffle() external view returns (address);
    function getWNative() external view returns (address);

    function quote(
        uint256 _amountA,
        uint256 _reserveA,
        uint256 _reserveB
    ) external pure returns (uint256);

    function getAmountOut(
        uint256 _amountIn,
        uint256 _reserveIn,
        uint256 _reserveOut,
        BubbleV1Types.Fraction memory _poolFee
    ) external pure returns (uint256);

    function getAmountIn(
        uint256 _amountOut,
        uint256 _reserveIn,
        uint256 _reserveOut,
        BubbleV1Types.Fraction memory _poolFee
    ) external pure returns (uint256);

    function getAmountsOut(
        uint256 _amountIn,
        address[] calldata _path
    ) external view returns (uint256[] memory);

    function getAmountsIn(
        uint256 _amountOut,
        address[] calldata _path
    ) external view returns (uint256[] memory);
}

/// @title BubbleV1Types.
/// @author Bubble Finance -- mgnfy-view.
/// @notice All type declarations for the protocol are collected here for convenience.
contract BubbleV1Types {
    /// @notice A fraction struct to store fee percentages, etc.
    struct Fraction {
        /// @dev The fraction numerator.
        uint256 numerator;
        /// @dev The fraction denominator.
        uint256 denominator;
    }

    /// @notice Users leveraging flash swaps and flash loans can execute custom
    /// logic before and after a swap by setting these values.
    struct HookConfig {
        /// @dev If true, invoke the `before swap hook` on the receiving contract.
        bool hookBeforeCall;
        /// @dev If true, invoke the `after swap hook` on the receiving contract.
        bool hookAfterCall;
    }

    /// @notice Packing parameters for swapping into a struct to avoid stack
    /// too deep errors. To be used by the `BubbleV1Pool` contract.
    struct SwapParams {
        /// @dev The amount of token A to send to the receiver.
        uint256 amountAOut;
        /// @dev The amount of token B to send to the receiver.
        uint256 amountBOut;
        /// @dev The address to which the token amounts are directed.
        address receiver;
        /// @dev Hook configuration parameters.
        HookConfig hookConfig;
        /// @dev Bytes data to pass to the flash swap or flash loan receiver.
        bytes data;
    }

    /// @notice Packing parameters required for adding liquidity in a struct
    /// to avoid stack too deep errors.
    struct AddLiquidity {
        /// @dev Address of token A.
        address tokenA;
        /// @dev Address of token B.
        address tokenB;
        /// @dev Maximum amount of token A to add as liquidity.
        uint256 amountADesired;
        /// @dev Maximum amount of token B to add as liquidity.
        uint256 amountBDesired;
        /// @dev Minimum amount of token A to add as liquidity.
        uint256 amountAMin;
        /// @dev Minimum amount of token B to add as liquidity.
        uint256 amountBMin;
        /// @dev The address to direct the LP tokens to.
        address receiver;
        /// @dev UNIX timestamp (in seconds) before which the liquidity should be added.
        uint256 deadline;
    }

    // ["0x3a98250F98Dd388C211206983453837C8365BDc1","0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701","3002129975671129909","3000000000000000000","1000000000000000000","2900000000000000000","0x53C02dDD9804E318472Dbe5c4297834A7B80BA0e","1746095340"]
// 0]: 0000000000000000000000003a98250f98dd388c211206983453837c8365bdc1
// [1]: 000000000000000000000000760afe86e5de5fa0ee542fc7b7b713e1c5425701
// [2]: 0000000000000000000000000000000000000000000000000de5e44c9039cf81
// [3]: 0000000000000000000000000000000000000000000000000de55fcb74e3a1fd
// [4]: 0000000000000000000000000000000000000000000000000de41ce390aa6bf1
// [5]: 0000000000000000000000000000000000000000000000000de398736b3b1229
// [6]: 00000000000000000000000053c02ddd9804e318472dbe5c4297834a7b80ba0e
// [7]: 000000000000000000000000000000000000000000000000000000006811b19a
    /// @notice Packing parameters required for adding native token liquidity in a struct
    /// to avoid stack too deep errors.
    struct AddLiquidityNative {
        /// @dev Address of token.
        address token;
        /// @dev Maximum amount of token to add as liquidity.
        uint256 amountTokenDesired;
        /// @dev Minimum amount of token to add as liquidity.
        uint256 amountTokenMin;
        /// @dev Minimum amount of native token to add as liquidity.
        uint256 amountNativeTokenMin;
        /// @dev The address to direct the LP tokens to.
        address receiver;
        /// @dev UNIX timestamp (in seconds) before which the liquidity should be added.
        uint256 deadline;
    }

    /// @notice Allows removal of liquidity from Bubble pools using a permit signature.
    struct RemoveLiquidityWithPermit {
        /// @dev Address of token A.
        address tokenA;
        /// @dev Address of token B.
        address tokenB;
        /// @dev Amount of LP tokens to burn.
        uint256 lpTokensToBurn;
        /// @dev Minimum amount of token A to withdraw from pool.
        uint256 amountAMin;
        /// @dev Minimum amount of token B to withdraw from pool.
        uint256 amountBMin;
        /// @dev The address to direct the withdrawn tokens to.
        address receiver;
        /// @dev The UNIX timestamp (in seconds) before which the liquidity should be removed.
        uint256 deadline;
        /// @dev Approve maximum amount (type(uint256).max) to the router or just the
        /// required LP token amount.
        bool approveMax;
        /// @dev The v part of the signature.
        uint8 v;
        /// @dev The r part of the signature.
        bytes32 r;
        /// @dev The s part of the signature.
        bytes32 s;
    }

    /// @notice Allows removal of native token liquidity from Bubble pools using a permit.
    /// Packing parameters in a struct to avoid stack too deep errors.
    struct RemoveLiquidityNativeWithPermit {
        /// @dev Address of token.
        address token;
        /// @dev Amount of LP tokens to burn.
        uint256 lpTokensToBurn;
        /// @dev Minimum amount of token to withdraw from pool.
        uint256 amountTokenMin;
        /// @dev Minimum amount of native token to withdraw from pool.
        uint256 amountNativeMin;
        /// @dev The address to direct the withdrawn tokens to.
        address receiver;
        /// @dev The UNIX timestamp (in seconds) before which the liquidity should be removed.
        uint256 deadline;
        /// @dev Approve maximum amount (type(uint256).max) to the router or just
        /// the required LP token amount.
        bool approveMax;
        /// @dev The v part of the signature.
        uint8 v;
        /// @dev The r part of the signature.
        bytes32 r;
        /// @dev The s part of the signature.
        bytes32 s;
    }

    /// @notice The Pyth price feed config for raffle.
    struct PriceFeedConfig {
        /// @dev The token/usd price feed id.
        bytes32 priceFeedId;
        /// @dev The max window after which the price feed will be considered stale.
        uint256 noOlderThan;
    }

    /// @notice Enter raffle during a swap on supported pools.
    struct Raffle {
        /// @dev True if the user wants to enter raffle, false otherwise.
        bool enter;
        /// @dev The fraction of swap amount that should be used to enter raffle.
        Fraction fractionOfSwapAmount;
        /// @dev The receiver of the raffle nft.
        address raffleNftReceiver;
    }

    /// @notice Raffle winning tiers.
    enum Tiers {
        TIER1,
        TIER2,
        TIER3
    }

    /// @notice Struct to return the amount of tokens a user has won in a raffle epoch.
    struct Winnings {
        /// @dev The token address.
        address token;
        /// @dev The token amount.
        uint256 amount;
    }

    /// @notice Raffle winnings claim struct to avoid stack too deep error.
    struct RaffleClaim {
        /// @dev The tier to claim winnings in.
        Tiers tier;
        /// @dev The epoch to claim winnings from.
        uint256 epoch;
        /// @dev The raffle Nft tokenId to claim winnings on behalf of.
        uint256 tokenId;
    }

    /// @notice Details of a token launched on `BubbleV1Campaigns`.
    struct TokenDetails {
        /// @dev The token name.
        string name;
        /// @dev The token ticker.
        string symbol;
        /// @dev The address of the creator of the token.
        address creator;
        /// @dev Tracks the amount of tokens held by the bonding curve.
        uint256 tokenReserve;
        /// @dev Tracks the amount of native token held by the bonding curve plus
        /// the initial virtual amount.
        uint256 nativeTokenReserve;
        /// @dev The initial virtual native token amount used to set the initial
        /// price of a token.
        uint256 virtualNativeTokenReserve;
        /// @dev The target native token amount to reach before listing the token
        /// on Bubble. This includes the initial virtual native token amount.
        uint256 targetNativeTokenReserve;
        /// @dev The reward (in native wrapped token) to be given to the token creator
        /// once the token is successfully listed on Bubble.
        uint256 tokenCreatorReward;
        /// @dev The fee taken by the protcol on each successful listing (in native
        /// token).
        uint256 liquidityMigrationFee;
        /// @dev Tells if the token has completed its bonding curve or not.
        bool launched;
    }
}
