// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library StargateOptionsBuilder {
    uint16 internal constant TYPE_3 = 3;
    uint8 internal constant WORKER_ID_EXECUTOR = 1;
    uint8 internal constant OPTION_TYPE_LZ_COMPOSE = 3;

    function newOptions() internal pure returns (bytes memory) {
        return abi.encodePacked(TYPE_3);
    }

    function addExecutorLzComposeOption(
        bytes memory options,
        uint16 index,
        uint128 gasLimit,
        uint128 value
    ) internal pure returns (bytes memory) {
        if (options.length == 0) {
            options = newOptions();
        }

        return abi.encodePacked(
            options,
            WORKER_ID_EXECUTOR,
            uint16(35),
            OPTION_TYPE_LZ_COMPOSE,
            index,
            gasLimit,
            value
        );
    }
}
