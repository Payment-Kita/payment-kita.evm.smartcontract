// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library GatewayEvents {
    event ModulesUpdated(address indexed validator, address indexed quoter, address indexed executor, address privacy);
    event FeePolicyManagerUpdated(address indexed oldManager, address indexed newManager);
}

