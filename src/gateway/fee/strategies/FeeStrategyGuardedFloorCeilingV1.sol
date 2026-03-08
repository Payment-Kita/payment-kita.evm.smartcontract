// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../../../interfaces/IFeeStrategy.sol";

contract FeeStrategyGuardedFloorCeilingV1 is IFeeStrategy, Ownable {
    error InvalidBounds();

    uint256 public floorFee;
    uint256 public ceilingFee;
    uint256 public bps;

    event GuardedParamsUpdated(uint256 floorFee, uint256 ceilingFee, uint256 bps);

    constructor(uint256 _floorFee, uint256 _ceilingFee, uint256 _bps) Ownable(msg.sender) {
        _setParams(_floorFee, _ceilingFee, _bps);
    }

    function setParams(uint256 _floorFee, uint256 _ceilingFee, uint256 _bps) external onlyOwner {
        _setParams(_floorFee, _ceilingFee, _bps);
    }

    function computePlatformFee(
        bytes calldata,
        bytes calldata,
        address,
        address,
        uint256 sourceAmount,
        uint256,
        uint256
    ) external view override returns (uint256 platformFee) {
        platformFee = (sourceAmount * bps) / 10_000;
        if (platformFee < floorFee) platformFee = floorFee;
        if (ceilingFee > 0 && platformFee > ceilingFee) platformFee = ceilingFee;
    }

    function _setParams(uint256 _floorFee, uint256 _ceilingFee, uint256 _bps) internal {
        if (_ceilingFee > 0 && _floorFee > _ceilingFee) revert InvalidBounds();
        floorFee = _floorFee;
        ceilingFee = _ceilingFee;
        bps = _bps;
        emit GuardedParamsUpdated(_floorFee, _ceilingFee, _bps);
    }
}

