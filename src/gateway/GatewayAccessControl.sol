// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

abstract contract GatewayAccessControl {
    function _requireNonZero(address value, string memory err) internal pure {
        require(value != address(0), err);
    }
}

