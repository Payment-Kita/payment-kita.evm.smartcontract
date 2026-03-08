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

        console.log("Gateway:", gateway);

        (bool hasGlobal, bool globalDisabled) = _readBool(
            gateway,
            abi.encodeWithSelector(IGatewayV1StatusView.v1DisabledGlobal.selector)
        );
        if (hasGlobal) {
            console.log("v1DisabledGlobal:", globalDisabled);
        } else {
            console.log("v1DisabledGlobal: <unsupported_on_gateway>");
        }

        if (bytes(destCaip2).length > 0) {
            console.log("dest:", destCaip2);
            (bool hasLane, bool laneDisabled) = _readBool(
                gateway,
                abi.encodeWithSelector(IGatewayV1StatusView.v1DisabledByDestCaip2.selector, destCaip2)
            );
            if (hasLane) {
                console.log("v1DisabledLane:", laneDisabled);
            } else {
                console.log("v1DisabledLane: <unsupported_on_gateway>");
            }
        }
    }

    function _readBool(address target, bytes memory data) internal view returns (bool ok, bool value) {
        bytes memory ret;
        (ok, ret) = target.staticcall(data);
        if (!ok || ret.length < 32) {
            return (false, false);
        }
        value = abi.decode(ret, (bool));
        return (true, value);
    }
}
