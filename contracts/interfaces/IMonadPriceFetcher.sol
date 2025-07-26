// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IMonadPriceFetcher {
    /// @notice Returns price of tokenIn in terms of tokenOut, scaled to 1e18
    function getPrice(address tokenIn, address tokenOut) external view returns (uint256 price);

    /// @notice Returns price of a token in WMONAD, scaled to 1e18
    function getPriceInWmonad(address token) external view returns (uint256 price);

    /// @notice Returns pair address and reserve details
    function getPairDetails(
        address tokenA,
        address tokenB
    )
        external
        view
        returns (
            address pairAddress_,
            address token0_,
            address token1_,
            uint112 reserve0_,
            uint112 reserve1_
        );

    function getTokenPrice(address token) external view returns (uint256);
    function getNFTPrice(address nftContract, uint256 tokenId) external view returns (uint256);
}
