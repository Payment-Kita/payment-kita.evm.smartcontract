// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../../../interfaces/IFeeStrategy.sol";

contract FeeStrategyMarketAdaptiveV1 is IFeeStrategy, Ownable {
    error InvalidBounds();

    uint256 public baseBps;
    uint256 public volatilityBoostBps;
    uint256 public minBps;
    uint256 public maxBps;

    event ParamsUpdated(uint256 baseBps, uint256 volatilityBoostBps, uint256 minBps, uint256 maxBps);

    constructor(
        uint256 _baseBps,
        uint256 _volatilityBoostBps,
        uint256 _minBps,
        uint256 _maxBps
    ) Ownable(msg.sender) {
        _setParams(_baseBps, _volatilityBoostBps, _minBps, _maxBps);
    }

    function setParams(
        uint256 _baseBps,
        uint256 _volatilityBoostBps,
        uint256 _minBps,
        uint256 _maxBps
    ) external onlyOwner {
        _setParams(_baseBps, _volatilityBoostBps, _minBps, _maxBps);
    }

    function computePlatformFee(
        bytes calldata,
        bytes calldata,
        address,
        address,
        uint256 sourceAmount,
        uint256,
        uint256 swapImpactBps
    ) external view override returns (uint256 platformFee) {
        uint256 dynamicBps = baseBps + ((swapImpactBps * volatilityBoostBps) / 10_000);
        if (dynamicBps < minBps) dynamicBps = minBps;
        if (dynamicBps > maxBps) dynamicBps = maxBps;
        platformFee = (sourceAmount * dynamicBps) / 10_000;
    }

    function _setParams(
        uint256 _baseBps,
        uint256 _volatilityBoostBps,
        uint256 _minBps,
        uint256 _maxBps
    ) internal {
        if (_minBps > _maxBps) revert InvalidBounds();
        baseBps = _baseBps;
        volatilityBoostBps = _volatilityBoostBps;
        minBps = _minBps;
        maxBps = _maxBps;
        emit ParamsUpdated(_baseBps, _volatilityBoostBps, _minBps, _maxBps);
    }
}

