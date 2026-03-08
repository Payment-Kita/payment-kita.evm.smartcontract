// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../../interfaces/IGatewayValidatorModule.sol";

interface ITokenRegistryValidator {
    function isTokenSupported(address token) external view returns (bool);
}

contract GatewayValidatorModule is Ownable, IGatewayValidatorModule {
    constructor() Ownable(msg.sender) {}

    function validateCreate(
        address tokenRegistry,
        bytes calldata receiverBytes,
        address sourceToken,
        address destToken,
        uint256 amount,
        bool requireSourceTokenSupported,
        bool requireDestTokenSupported
    ) external view override returns (address receiver) {
        require(amount > 0, "Amount must be > 0");
        require(sourceToken != address(0), "Invalid source token");
        require(receiverBytes.length > 0, "Empty receiver");

        receiver = abi.decode(receiverBytes, (address));
        require(receiver != address(0), "Invalid receiver address");

        ITokenRegistryValidator registry = ITokenRegistryValidator(tokenRegistry);
        if (requireSourceTokenSupported) {
            require(registry.isTokenSupported(sourceToken), "Source token not supported");
        }
        if (requireDestTokenSupported) {
            require(destToken != address(0), "Invalid destination token");
            require(registry.isTokenSupported(destToken), "Destination token not supported");
        }
    }
}
