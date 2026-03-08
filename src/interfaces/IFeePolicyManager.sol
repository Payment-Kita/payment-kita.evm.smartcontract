// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IFeeStrategy.sol";

interface IFeePolicyManager {
    function resolveStrategy() external view returns (IFeeStrategy);

    function computePlatformFee(
        bytes calldata sourceChainId,
        bytes calldata destChainId,
        address sourceToken,
        address destToken,
        uint256 amount,
        uint256 bridgeFeeNative,
        uint256 swapImpactBps,
        bool policyEnabled,
        uint256 payloadLength,
        uint256 policyOverheadBytes,
        uint256 policyPerByteRate,
        uint256 policyMinFee,
        uint256 policyMaxFee,
        uint256 fixedBaseFee,
        uint256 feeRateBps
    ) external view returns (uint256);
}
