// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MySwapper {
    function callAggregatorSwap(address aggregator, bytes calldata data) external {
    (bool success, bytes memory result) = aggregator.call(data);
    require(success, "Aggregator swap failed");
}
function callAggregatorSwapWithValue(address aggregator, bytes calldata data) external payable {
    (bool success, bytes memory result) = aggregator.call{value: msg.value}(data);
    require(success, "Aggregator swap failed");
}
}
contract OptimizedSwapper {
    // address public constant AGGREGATOR = 0xC995498c22a012353FAE7eCC701810D673E25794;
    IAggregator public immutable aggregator;
    constructor(IAggregator _aggregator){
        aggregator=_aggregator;
    }
    function callAggregatorSwap( bytes calldata data,uint toknAmnt,address tknAddr) external {

    IERC20(tknAddr).transferFrom(msg.sender,address(this),toknAmnt);
    IERC20(tknAddr).approve(address(aggregator),toknAmnt);
    (bool success, bytes memory result) = address(aggregator).call(data);

    require(success, "Aggregator swap failed");
}}

interface IAggregator {
    // Events
    event Aggregation(
        address indexed tokenAddress,
        address indexed outTokenAddress,
        uint256 amount,
        uint256 destinationAmount,
        uint256 feeAmount
    );
    
    event FeeMultiplierUpdated(uint256 oldFeeMultiplier, uint256 newFeeMultiplier);
    event FeeReceiverUpdated(address indexed oldFeeReceiver, address indexed newFeeReceiver);
    event NativeSenderAllowlistUpdated(address indexed sender, bool allowed);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event TargetAllowlistUpdated(address indexed target, bool allowed);

    // Errors
    error CallFailed(bytes data);
    error InsufficientOutput();
    error InvalidAddress();
    error InvalidAmount();
    error InvalidArrayLength();
    error InvalidFeeReceiver();
    error OwnableInvalidOwner(address owner);
    error OwnableUnauthorizedAccount(address account);
    error ReentrancyGuardReentrantCall();
    error SafeERC20FailedOperation(address token);
    error TransactionExpired();
    error TransferFailed();
    error UnauthorizedTarget();

    // View functions
    function NATIVE_ADDRESS() external view returns (address);
    function allowedNativeSenders(address sender) external view returns (bool);
    function allowedTargets(address target) external view returns (bool);
    function feeMultiplier() external view returns (uint256);
    function feeReceiver() external view returns (address);
    function owner() external view returns (address);

    // Transaction functions
    function aggregate(
        address tokenAddress,
        address outTokenAddress,
        uint256 amount,
        address[] calldata targets,
        bytes[] calldata data,
        address destination,
        uint256 minOutAmount,
        uint256 deadline
    ) external ;

    function batchSetTargetAllowlist(
        address[] calldata targets,
        bool[] calldata allowed
    ) external;

    function renounceOwnership() external;

    function setAllowedNativeSender(
        address sender,
        bool allowed
    ) external;

    function setFeeMultiplier(
        uint256 newFeeBps
    ) external;

    function setFeeReceiver(
        address newFeeReceiver
    ) external;

    function setTargetAllowlist(
        address target,
        bool allowed
    ) external;

    function transferOwnership(
        address newOwner
    ) external;

    receive() external payable;
    fallback() external payable;  // <-- add this line to enable fallback
}

contract Caller {
    function callFallbackWithCalldata(address target, bytes calldata data) external payable {
        (bool success, bytes memory returnData) = target.call{value: msg.value}(data);
        require(success, "Fallback call failed");
    }
}