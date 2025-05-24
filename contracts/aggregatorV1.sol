// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./vaultV1.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract AggregatorV1 is ReentrancyGuard {
    address public native=address(0);
    
    function aggreagteAndJoin(
        uint256 amountIn,
        address inputToken,
        address aggregator,
        bytes calldata data
        )external payable  nonReentrant{
            
                require(native == inputToken, "Incorrect msg.value for native");
                require(msg.value == amountIn, "Incorrect msg.value for native");
                (bool success, ) = aggregator.call{value: amountIn}(data);
            require(success, "Aggregator native swap failed");
            
        }
receive() external payable {}
}
// 0x0000000000000000000000000000000000000000
// 0x0000000000000000000000000000000000000000