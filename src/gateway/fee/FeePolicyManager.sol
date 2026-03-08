// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../../interfaces/IFeePolicyManager.sol";
import "../../interfaces/IFeeStrategy.sol";
import "../../libraries/FeeCalculator.sol";

contract FeePolicyManager is Ownable, IFeePolicyManager {
    error InvalidStrategy();

    IFeeStrategy public defaultStrategy;
    IFeeStrategy public activeStrategy;

    event DefaultStrategyUpdated(address indexed strategy);
    event ActiveStrategyUpdated(address indexed strategy);

    constructor(address _defaultStrategy) Ownable(msg.sender) {
        if (_defaultStrategy == address(0)) revert InvalidStrategy();
        defaultStrategy = IFeeStrategy(_defaultStrategy);
        emit DefaultStrategyUpdated(_defaultStrategy);
    }

    function setDefaultStrategy(address strategy) external onlyOwner {
        if (strategy == address(0)) revert InvalidStrategy();
        defaultStrategy = IFeeStrategy(strategy);
        emit DefaultStrategyUpdated(strategy);
    }

    function setActiveStrategy(address strategy) external onlyOwner {
        if (strategy == address(0)) revert InvalidStrategy();
        activeStrategy = IFeeStrategy(strategy);
        emit ActiveStrategyUpdated(strategy);
    }

    function clearActiveStrategy() external onlyOwner {
        activeStrategy = IFeeStrategy(address(0));
        emit ActiveStrategyUpdated(address(0));
    }

    function resolveStrategy() external view override returns (IFeeStrategy) {
        if (address(activeStrategy) != address(0)) {
            return activeStrategy;
        }
        return defaultStrategy;
    }

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
    ) external view override returns (uint256) {
        if (policyEnabled) {
            return FeeCalculator.calculatePerBytePlatformFee(
                payloadLength,
                policyOverheadBytes,
                policyPerByteRate,
                policyMinFee,
                policyMaxFee
            );
        }

        IFeeStrategy strategy = activeStrategy;
        if (address(strategy) == address(0)) {
            strategy = defaultStrategy;
        }

        if (address(strategy) != address(0)) {
            try
                strategy.computePlatformFee(
                    sourceChainId,
                    destChainId,
                    sourceToken,
                    destToken,
                    amount,
                    bridgeFeeNative,
                    swapImpactBps
                )
            returns (uint256 strategyFee) {
                return strategyFee;
            } catch {
                // fall through to legacy fee policy fallback
            }
        }

        return FeeCalculator.calculatePlatformFee(amount, fixedBaseFee, feeRateBps);
    }
}
