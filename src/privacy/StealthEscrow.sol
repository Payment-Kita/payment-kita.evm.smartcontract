// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Privacy escrow that can only be forwarded by an authorized module/executor.
contract StealthEscrow is Ownable {
    using SafeERC20 for IERC20;

    error UnauthorizedForwarder(address caller);
    error InvalidForwarder();
    error InvalidReceiver();
    error InvalidToken();
    error InvalidAmount();

    address public forwarder;

    event ForwarderUpdated(address indexed oldForwarder, address indexed newForwarder);
    event EscrowForwarded(address indexed token, address indexed receiver, uint256 amount);
    event EscrowNativeForwarded(address indexed receiver, uint256 amount);

    constructor(address owner_, address forwarder_) Ownable(owner_) {
        if (forwarder_ == address(0)) revert InvalidForwarder();
        forwarder = forwarder_;
    }

    modifier onlyForwarder() {
        if (msg.sender != forwarder) revert UnauthorizedForwarder(msg.sender);
        _;
    }

    function setForwarder(address newForwarder) external onlyOwner {
        if (newForwarder == address(0)) revert InvalidForwarder();
        emit ForwarderUpdated(forwarder, newForwarder);
        forwarder = newForwarder;
    }

    function forwardToken(address token, address receiver, uint256 amount) external onlyForwarder {
        if (token == address(0)) revert InvalidToken();
        if (receiver == address(0)) revert InvalidReceiver();
        if (amount == 0) revert InvalidAmount();

        IERC20(token).safeTransfer(receiver, amount);
        emit EscrowForwarded(token, receiver, amount);
    }

    function forwardNative(address payable receiver, uint256 amount) external onlyForwarder {
        if (receiver == address(0)) revert InvalidReceiver();
        if (amount == 0) revert InvalidAmount();

        (bool ok,) = receiver.call{value: amount}("");
        require(ok, "NATIVE_FORWARD_FAILED");
        emit EscrowNativeForwarded(receiver, amount);
    }

    receive() external payable {}
}
