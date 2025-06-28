// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./vaultV1.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract AggregatorV2 is ReentrancyGuard {
    address public native=address(0);
    
    function aggregateAndJoin(
        address vaultAddr,
        uint amountOut,
        address outputToken,
        uint256 amountIn,
        address inputToken,
        address receiver,
        address aggregator,
        bytes calldata data
        )external payable  nonReentrant{
            if(inputToken==native){
                require(msg.value == amountIn, "Incorrect msg.value for native");
                (bool success, ) = aggregator.call{value: msg.value}(data);
            require(success, "Aggregator native swap failed");
            }else{
 
            IERC20(inputToken).transferFrom(msg.sender,address(this),amountIn);
            IERC20(inputToken).approve(address(aggregator),amountIn);
    (bool success, bytes memory result) = (aggregator).call(data);
    require(success, "Aggregator swap failed");
            }
           

        
        IERC20(outputToken).approve(vaultAddr, 0);
        IERC20(outputToken).approve(vaultAddr,amountOut);
        BubbleLPVault(vaultAddr).joinSingle(
        amountOut,
        outputToken,
        receiver);
        }
receive() external payable {}
}
