// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/utils/math/Math.sol";

interface IBubbleVault {
    /// @notice Returns the amount of underlying assets that would be redeemed for the given shares
    /// @param shares The number of shares to redeem
    /// @return The amount of underlying assets corresponding to the shares
    function previewRedeem(uint256 shares) external view returns (uint256);

    /// @notice Redeem shares for underlying tokens
    /// @param shares The number of shares to redeem
    /// @param receiver The address to receive redeemed tokens
    /// @param owner The owner of the shares being redeemed
    /// @return amountA The amount of tokenA received
    /// @return amountB The amount of tokenB received
    function reclaim(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 amountA, uint256 amountB);
}
