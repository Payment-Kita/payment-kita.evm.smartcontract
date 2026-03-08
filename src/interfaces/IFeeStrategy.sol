// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IFeeStrategy {
    function computePlatformFee(
        bytes calldata sourceChainId,
        bytes calldata destChainId,
        address sourceToken,
        address destToken,
        uint256 sourceAmount,
        uint256 bridgeFeeNative,
        uint256 swapImpactBps
    ) external view returns (uint256 platformFee);
}

