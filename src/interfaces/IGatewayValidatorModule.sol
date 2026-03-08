// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IGatewayValidatorModule {
    function validateCreate(
        address tokenRegistry,
        bytes calldata receiverBytes,
        address sourceToken,
        address destToken,
        uint256 amount,
        bool requireSourceTokenSupported,
        bool requireDestTokenSupported
    ) external view returns (address receiver);
}
