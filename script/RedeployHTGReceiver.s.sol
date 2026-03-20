// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/integrations/hyperbridge/HyperbridgeTokenReceiverAdapter.sol";

interface IRedeployGateway {
    function setAuthorizedAdapter(address adapter, bool authorized) external;
    function isAuthorizedAdapter(address adapter) external view returns (bool);
}

interface IRedeployVault {
    function setAuthorizedSpender(address spender, bool authorized) external;
    function authorizedSpenders(address spender) external view returns (bool);
}

interface IRedeploySwapper {
    function setAuthorizedCaller(address caller, bool allowed) external;
    function authorizedCallers(address caller) external view returns (bool);
}

/**
 * @title RedeployHTGReceiver
 * @notice Redeploy HyperbridgeTokenReceiverAdapter, rewire authorizations, deauthorize old adapter.
 *
 * Required env:
 *   PRIVATE_KEY
 *   HTG_REDEPLOY_TOKEN_GATEWAY    - Hyperbridge TokenGateway host
 *   HTG_REDEPLOY_GATEWAY          - PaymentKitaGateway
 *   HTG_REDEPLOY_VAULT            - PaymentKitaVault
 *   HTG_REDEPLOY_SWAPPER          - TokenSwapper
 *   HTG_REDEPLOY_OLD_RECEIVER     - old adapter to deauthorize
 *
 * Optional env:
 *   HTG_REDEPLOY_SKIP_DEAUTH      - skip deauthorization of old adapter (default: false)
 */
contract RedeployHTGReceiver is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");

        address tokenGateway = vm.envAddress("HTG_REDEPLOY_TOKEN_GATEWAY");
        address gatewayAddr  = vm.envAddress("HTG_REDEPLOY_GATEWAY");
        address vaultAddr    = vm.envAddress("HTG_REDEPLOY_VAULT");
        address swapperAddr  = vm.envAddress("HTG_REDEPLOY_SWAPPER");
        address oldReceiver  = vm.envAddress("HTG_REDEPLOY_OLD_RECEIVER");
        bool skipDeauth      = vm.envOr("HTG_REDEPLOY_SKIP_DEAUTH", false);

        require(tokenGateway != address(0), "Missing tokenGateway");
        require(gatewayAddr  != address(0), "Missing gateway");
        require(vaultAddr    != address(0), "Missing vault");
        require(swapperAddr  != address(0), "Missing swapper");
        require(oldReceiver  != address(0), "Missing oldReceiver");

        IRedeployGateway gateway = IRedeployGateway(gatewayAddr);
        IRedeployVault   vault   = IRedeployVault(vaultAddr);
        IRedeploySwapper swapper = IRedeploySwapper(swapperAddr);

        vm.startBroadcast(pk);

        // 1. Deploy new adapter
        HyperbridgeTokenReceiverAdapter newAdapter = new HyperbridgeTokenReceiverAdapter(
            tokenGateway,
            gatewayAddr,
            vaultAddr
        );
        console.log("New HTG Receiver deployed at:", address(newAdapter));

        // 2. Wire swapper
        newAdapter.setSwapper(swapperAddr);
        console.log("Swapper set on new adapter");

        // 3. Authorize new adapter
        gateway.setAuthorizedAdapter(address(newAdapter), true);
        console.log("New adapter authorized on Gateway");

        vault.setAuthorizedSpender(address(newAdapter), true);
        console.log("New adapter authorized on Vault");

        swapper.setAuthorizedCaller(address(newAdapter), true);
        console.log("New adapter authorized on Swapper");

        // 4. Deauthorize old adapter
        if (!skipDeauth) {
            gateway.setAuthorizedAdapter(oldReceiver, false);
            console.log("Old adapter deauthorized on Gateway");

            vault.setAuthorizedSpender(oldReceiver, false);
            console.log("Old adapter deauthorized on Vault");

            swapper.setAuthorizedCaller(oldReceiver, false);
            console.log("Old adapter deauthorized on Swapper");
        } else {
            console.log("Skipping old adapter deauthorization (HTG_REDEPLOY_SKIP_DEAUTH=true)");
        }

        vm.stopBroadcast();

        // 5. Post-checks
        console.log("=== Post-deployment checks ===");
        console.log("New adapter:", address(newAdapter));
        console.log("Old adapter:", oldReceiver);

        bool newAuth = gateway.isAuthorizedAdapter(address(newAdapter));
        console.log("New adapter authorized on gateway:", newAuth);
        require(newAuth, "POST-CHECK FAIL: new adapter not authorized on gateway");

        if (!skipDeauth) {
            bool oldAuth = gateway.isAuthorizedAdapter(oldReceiver);
            console.log("Old adapter authorized on gateway:", oldAuth);
            require(!oldAuth, "POST-CHECK FAIL: old adapter still authorized on gateway");
        }

        console.log("=== RedeployHTGReceiver complete ===");
    }
}
