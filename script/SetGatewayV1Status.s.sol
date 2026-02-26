// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IGatewayV1StatusSetter {
    function setV1LaneDisabled(string calldata destChainId, bool disabled) external;
    function setV1GlobalDisabled(bool disabled) external;
}

contract SetGatewayV1Status is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address gateway = vm.envAddress("GATEWAY_V1_STATUS_GATEWAY");
        string memory mode = vm.envOr("GATEWAY_V1_STATUS_MODE", string("lane"));
        bool disabled = vm.envOr("GATEWAY_V1_STATUS_DISABLED", true);

        vm.startBroadcast(pk);

        if (_eq(mode, "global")) {
            IGatewayV1StatusSetter(gateway).setV1GlobalDisabled(disabled);
            console.log("setV1GlobalDisabled:", disabled);
        } else {
            string memory destCaip2 = vm.envString("GATEWAY_V1_STATUS_DEST_CAIP2");
            IGatewayV1StatusSetter(gateway).setV1LaneDisabled(destCaip2, disabled);
            console.log("setV1LaneDisabled:", destCaip2, disabled);
        }

        vm.stopBroadcast();
        console.log("Gateway:", gateway);
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}

