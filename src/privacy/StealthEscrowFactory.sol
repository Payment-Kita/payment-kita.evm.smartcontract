// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./StealthEscrow.sol";

/// @notice Factory to deploy deterministic stealth escrows.
contract StealthEscrowFactory {
    error EscrowAlreadyDeployed(address escrow);

    event StealthEscrowDeployed(address indexed escrow, address indexed owner, address indexed forwarder, bytes32 salt);

    mapping(address => bool) public isEscrow;

    function deployEscrow(bytes32 salt, address owner, address forwarder) external returns (address escrow) {
        escrow = predictEscrow(salt, owner, forwarder);
        if (escrow.code.length != 0 || isEscrow[escrow]) revert EscrowAlreadyDeployed(escrow);

        escrow = address(new StealthEscrow{salt: salt}(owner, forwarder));
        isEscrow[escrow] = true;

        emit StealthEscrowDeployed(escrow, owner, forwarder, salt);
    }

    function predictEscrow(bytes32 salt, address owner, address forwarder) public view returns (address) {
        bytes memory bytecode = abi.encodePacked(type(StealthEscrow).creationCode, abi.encode(owner, forwarder));
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(bytecode)
            )
        );
        return address(uint160(uint256(hash)));
    }
}
