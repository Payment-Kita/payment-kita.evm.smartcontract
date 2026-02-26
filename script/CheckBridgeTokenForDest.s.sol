// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IGatewayBridgeTokenView {
    function bridgeTokenByDestCaip2(string calldata destChainId) external view returns (address);
}

contract CheckBridgeTokenForDest is Script {
    function run() external view {
        address gateway = vm.envAddress("BRIDGE_TOKEN_GATEWAY");
        string memory destCaip2 = vm.envString("BRIDGE_TOKEN_DEST_CAIP2");
        address configured = IGatewayBridgeTokenView(gateway).bridgeTokenByDestCaip2(destCaip2);

        console.log("Gateway:", gateway);
        console.log("Dest:", destCaip2);
        console.log("Configured bridge token:", configured);
    }
}

