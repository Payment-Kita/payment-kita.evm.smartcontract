// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library GatewayTypes {
    struct Modules {
        address validator;
        address quoter;
        address executor;
        address privacy;
    }
}

