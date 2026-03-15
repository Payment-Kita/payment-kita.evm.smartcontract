// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title RescuableAdapter
 * @notice Provides owner-only functions to rescue stuck ERC20 and native tokens.
 */
abstract contract RescuableAdapter is Ownable {
    using SafeERC20 for IERC20;

    event TokenRescued(address indexed token, address indexed to, uint256 amount);
    event NativeRescued(address indexed to, uint256 amount);

    error RescueTransferFailed();

    /**
     * @notice Rescue stuck ERC20 tokens from the adapter.
     * @param token The ERC20 token to rescue.
     * @param to The recipient address.
     * @param amount The amount to rescue.
     */
    function rescueToken(IERC20 token, address to, uint256 amount) external onlyOwner {
        token.safeTransfer(to, amount);
        emit TokenRescued(address(token), to, amount);
    }

    /**
     * @notice Rescue stuck native tokens (ETH/POL) from the adapter.
     * @param to The recipient address.
     * @param amount The amount to rescue.
     */
    function rescueNative(address payable to, uint256 amount) external onlyOwner {
        (bool success, ) = to.call{value: amount}("");
        if (!success) revert RescueTransferFailed();
        emit NativeRescued(to, amount);
    }
}
