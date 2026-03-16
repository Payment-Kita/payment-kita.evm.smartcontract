// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/integrations/stargate/StargateReceiverAdapter.sol";

interface IRescueGateway {
    function setAuthorizedAdapter(address adapter, bool authorized) external;
}

interface IRescueVault {
    function setAuthorizedSpender(address spender, bool authorized) external;
}

interface IRescueSwapper {
    function setAuthorizedCaller(address caller, bool allowed) external;
}

contract DeployStargateRescuableReceiver is Script {
    error MissingEnv(string name);

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");

        address gatewayAddr = vm.envAddress("GATEWAY_CONTRACT");
        if (gatewayAddr == address(0)) revert MissingEnv("GATEWAY_CONTRACT");

        address vaultAddr = vm.envAddress("VAULT_CONTRACT");
        if (vaultAddr == address(0)) revert MissingEnv("VAULT_CONTRACT");

        address swapperAddr = vm.envOr("SWAPPER_CONTRACT", address(0));

        address endpoint = vm.envAddress("LAYERZERO_ENDPOINT");
        if (endpoint == address(0)) revert MissingEnv("LAYERZERO_ENDPOINT");

        uint32 srcEid = uint32(vm.envUint("STARGATE_SRC_EID"));
        address trustedStargate = vm.envAddress("TRUSTED_STARGATE_POOL");
        address receivedToken = vm.envAddress("RECEIVED_TOKEN");

        address oldReceiver = vm.envOr("OLD_RECEIVER", address(0));

        vm.startBroadcast(pk);

        // 1. Deploy the new Rescuable Receiver
        StargateReceiverAdapter receiver = new StargateReceiverAdapter(
            endpoint,
            gatewayAddr,
            vaultAddr
        );

        // 2. Configure paths and swapper
        receiver.setRoute(srcEid, trustedStargate, receivedToken);
        if (swapperAddr != address(0)) {
            receiver.setSwapper(swapperAddr);
        }

        // 3. Authorize new receiver
        IRescueVault(vaultAddr).setAuthorizedSpender(address(receiver), true);
        IRescueGateway(gatewayAddr).setAuthorizedAdapter(address(receiver), true);
        if (swapperAddr != address(0)) {
            IRescueSwapper(swapperAddr).setAuthorizedCaller(address(receiver), true);
        }

        // 4. Deauthorize old receiver if provided
        if (oldReceiver != address(0)) {
            IRescueVault(vaultAddr).setAuthorizedSpender(oldReceiver, false);
            IRescueGateway(gatewayAddr).setAuthorizedAdapter(oldReceiver, false);
            // Swapper usually doesn't have deauthorize caller in the simple interface, 
            // but can be added if supported by the token swapper.
        }

        vm.stopBroadcast();

        console.log("Deployed New Rescuable StargateReceiverAdapter at:", address(receiver));
        console.log("Wired to Gateway:", gatewayAddr);
        console.log("Wired to Vault:", vaultAddr);
        if (oldReceiver != address(0)) {
            console.log("Deauthorized Old Receiver:", oldReceiver);
        }
    }
}
