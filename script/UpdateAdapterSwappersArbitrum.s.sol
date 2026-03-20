// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

interface ISwapperReceiver {
    function setSwapper(address _swapper) external;
}

/**
 * @title UpdateAdapterSwappersArbitrum
 * @notice Script to update the TokenSwapper reference in all receiving adapters on Arbitrum.
 */
contract UpdateAdapterSwappersArbitrum is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");

        // New TokenSwapper address
        address newSwapper = 0x0B482Cc728A9AAf9BfBFDD24247B181aF0238295;

        // Adapter addresses on Arbitrum (with correct checksums)
        address ccipReceiver = 0x0078f08C7A1c3daB5986F00Dc4E32018a95Ee195;
        address hbReceiver = 0xF46c1fCff7e42bACF3B769C2364fFb86Ca52FCF6;
        address stargateReceiver = 0xA0502C041AAE8Ae1A4141D7E7937b34A01510fcf;

        vm.startBroadcast(pk);

        console.log("Updating CCIPReceiverAdapter swapper...");
        ISwapperReceiver(ccipReceiver).setSwapper(newSwapper);

        console.log("Updating HyperbridgeReceiver swapper...");
        ISwapperReceiver(hbReceiver).setSwapper(newSwapper);

        console.log("Updating StargateReceiverAdapter swapper...");
        ISwapperReceiver(stargateReceiver).setSwapper(newSwapper);

        vm.stopBroadcast();

        console.log("UpdateAdapterSwappersArbitrum completed successfully.");
    }
}
