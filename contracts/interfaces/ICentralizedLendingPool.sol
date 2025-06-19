// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface ICentralizedLendingPool {
    /**
     * @dev Deposit USDC into the lending pool
     * @param lender Address of the lender
     * @param amount Amount of USDC to deposit
     * @param vault Address of the vault that initiated the deposit
     */
    function deposit(address lender, uint256 amount, address vault) external;

    /**
     * @dev Withdraw USDC from the lending pool
     * @param lender Address of the lender
     * @param amount Amount of USDC to withdraw
     * @param vault Address of the vault that initiated the withdrawal
     */
    function withdraw(address lender, uint256 amount, address vault) external;

    /**
     * @dev Borrow USDC from the lending pool (called by vaults)
     * @param vault Address of the vault borrowing
     * @param amount Amount of USDC to borrow
     */
    function borrow(address vault, uint256 amount) external;

    /**
     * @dev Repay USDC to the lending pool (called by vaults)
     * @param vault Address of the vault repaying
     * @param amount Amount of USDC to repay
     */
    function repay(address vault, uint256 amount) external;

    /**
     * @dev Distribute interest to lenders
     * @param amount Amount of interest to distribute
     */
    function distributeInterest(uint256 amount) external;

    /**
     * @dev Get total deposits in the lending pool
     * @return Total amount of USDC deposited
     */
    function getTotalDeposits() external view returns (uint256);

    /**
     * @dev Get available liquidity for borrowing
     * @return Available USDC for borrowing
     */
    function getAvailableLiquidity() external view returns (uint256);

    /**
     * @dev Get lender's deposit amount
     * @param lender Address of the lender
     * @return Deposit amount
     */
    function getLenderDeposit(address lender) external view returns (uint256);

    /**
     * @dev Get lender's accrued interest
     * @param lender Address of the lender
     * @return Accrued interest amount
     */
    function getLenderInterest(address lender) external view returns (uint256);

    /**
     * @dev Get total borrowed amount
     * @return Total amount borrowed by all vaults
     */
    function getTotalBorrowed() external view returns (uint256);

    /**
     * @dev Get vault's borrowed amount
     * @param vault Address of the vault
     * @return Borrowed amount by the vault
     */
    function getVaultBorrowed(address vault) external view returns (uint256);


    function getVaultInterestRate(address vault) external view returns (
        uint256 baseRate,
        uint256 multiplier,
        uint256 jumpMultiplier,
        uint256 kink,
        uint256 lenderShare,
        uint256 vaultFeeRate,
        uint256 protocolFeeRate
    );

    /**
     * @dev Get total interest paid by a vault (in USDC)
     * @param vault Address of the vault
     * @return Total interest paid by this vault
     */
    function getVaultTotalInterestPaid(address vault) external view returns (uint256);
    /**
 * @dev Get the total interest ever distributed to all lenders (in USDC)
 * @return Total interest distributed
 */
function getTotalInterestDistributed() external view returns (uint256);
} 