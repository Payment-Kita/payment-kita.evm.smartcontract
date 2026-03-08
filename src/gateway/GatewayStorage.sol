// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./GatewayTypes.sol";

library GatewayStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("paymentkita.gateway.modular.storage.v1");

    struct Layout {
        GatewayTypes.Modules modules;
        address feePolicyManager;
    }

    function layout() internal pure returns (Layout storage s) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }
}

