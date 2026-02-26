// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IGatewaySetBridgeToken {
    function setBridgeTokenForDest(string calldata destChainId, address bridgeTokenSource) external;
}

contract SetBridgeTokenForDest is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address gateway = vm.envAddress("BRIDGE_TOKEN_GATEWAY");
        string memory destCaip2 = vm.envString("BRIDGE_TOKEN_DEST_CAIP2");
        address bridgeToken = vm.envAddress("BRIDGE_TOKEN_SOURCE_TOKEN");

        vm.startBroadcast(pk);
        IGatewaySetBridgeToken(gateway).setBridgeTokenForDest(destCaip2, bridgeToken);
        vm.stopBroadcast();

        console.log("setBridgeTokenForDest complete");
        console.log("Gateway:", gateway);
        console.log("Dest:", destCaip2);
        console.log("Bridge token:", bridgeToken);
    }
}

