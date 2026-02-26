// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IGatewayV1StatusView {
    function v1DisabledGlobal() external view returns (bool);
    function v1DisabledByDestCaip2(string calldata destChainId) external view returns (bool);
}

contract CheckGatewayV1Status is Script {
    function run() external {
        address gateway = vm.envAddress("GATEWAY_V1_STATUS_GATEWAY");
        string memory destCaip2 = vm.envOr("GATEWAY_V1_STATUS_DEST_CAIP2", string(""));

        bool globalDisabled = IGatewayV1StatusView(gateway).v1DisabledGlobal();
        console.log("Gateway:", gateway);
        console.log("v1DisabledGlobal:", globalDisabled);

        if (bytes(destCaip2).length > 0) {
            bool laneDisabled = IGatewayV1StatusView(gateway).v1DisabledByDestCaip2(destCaip2);
            console.log("dest:", destCaip2);
            console.log("v1DisabledLane:", laneDisabled);
        }
    }
}
