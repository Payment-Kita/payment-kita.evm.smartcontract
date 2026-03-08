// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../../interfaces/IFeeStrategy.sol";
import "../../../libraries/FeeCalculator.sol";

contract FeeStrategyDefaultV1 is IFeeStrategy {
    uint256 public constant FIXED_BASE_FEE = 0.50e6;
    uint256 public constant FEE_RATE_BPS = 30;

    function computePlatformFee(
        bytes calldata,
        bytes calldata,
        address,
        address,
        uint256 sourceAmount,
        uint256,
        uint256
    ) external pure override returns (uint256 platformFee) {
        platformFee = FeeCalculator.calculatePlatformFee(sourceAmount, FIXED_BASE_FEE, FEE_RATE_BPS);
    }
}
