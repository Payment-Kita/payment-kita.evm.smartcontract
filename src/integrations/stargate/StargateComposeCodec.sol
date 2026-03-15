// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library StargateComposeCodec {
    uint256 internal constant NONCE_OFFSET = 0;
    uint256 internal constant SRC_EID_OFFSET = 8;
    uint256 internal constant AMOUNT_LD_OFFSET = 12;
    uint256 internal constant COMPOSE_FROM_OFFSET = 44;
    uint256 internal constant COMPOSE_MSG_OFFSET = 76;

    function nonce(bytes calldata message) internal pure returns (uint64 value) {
        value = uint64(bytes8(message[NONCE_OFFSET:SRC_EID_OFFSET]));
    }

    function srcEid(bytes calldata message) internal pure returns (uint32 value) {
        value = uint32(bytes4(message[SRC_EID_OFFSET:AMOUNT_LD_OFFSET]));
    }

    function amountLD(bytes calldata message) internal pure returns (uint256 value) {
        value = uint256(bytes32(message[AMOUNT_LD_OFFSET:COMPOSE_FROM_OFFSET]));
    }

    function composeFrom(bytes calldata message) internal pure returns (bytes32 value) {
        value = bytes32(message[COMPOSE_FROM_OFFSET:COMPOSE_MSG_OFFSET]);
    }

    function composeMsg(bytes calldata message) internal pure returns (bytes calldata payload) {
        payload = message[COMPOSE_MSG_OFFSET:];
    }
}
