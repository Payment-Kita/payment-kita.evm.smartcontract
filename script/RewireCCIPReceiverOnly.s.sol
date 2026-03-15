// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../src/integrations/ccip/CCIPReceiver.sol";

interface ICCIPSenderRewire {
    function setDestinationAdapter(string calldata chainId, bytes calldata adapter) external;
    function setDestinationGasLimit(string calldata chainId, uint256 gasLimit) external;
    function setDestinationExtraArgs(string calldata chainId, bytes calldata extraArgs) external;
    function destinationGasLimits(string calldata chainId) external view returns (uint256);
    function destinationAdapters(string calldata chainId) external view returns (bytes memory);
}

interface IGatewayCCIPRewire {
    function setAuthorizedAdapter(address adapter, bool authorized) external;
}

interface IVaultCCIPRewire {
    function setAuthorizedSpender(address spender, bool authorized) external;
    function authorizedSpenders(address spender) external view returns (bool);
}

interface ISwapperCCIPRewire {
    function setAuthorizedCaller(address caller, bool allowed) external;
}

interface ICCIPReceiverViewRewire {
    function trustedSenders(uint64 chainSelector) external view returns (bytes memory);
    function allowedSourceChains(uint64 chainSelector) external view returns (bool);
}

contract RewireCCIPReceiverOnly is Script {
    address internal constant CCIP_ROUTER_BASE = 0x881e3A65B4d4a04dD529061dd0071cf975F58bCD;
    address internal constant CCIP_ROUTER_ARBITRUM = 0x141fa059441E0ca23ce184B6A78bafD2A517DdE8;

    uint64 internal constant SELECTOR_BASE = 15971525489660198786;
    uint64 internal constant SELECTOR_ARBITRUM = 4949039107694359620;

    struct RewireConfig {
        address ccipRouter;
        address gateway;
        address vault;
        address swapper;
        address senderToKeep;
        address oldReceiver;
        string destCaip2;
        uint64 sourceSelector;
        address sourceTrustedSender;
        uint256 destGasLimit;
        bytes destExtraArgs;
        bool updateGasLimit;
        bool updateExtraArgs;
        bool deauthorizeOld;
    }

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        RewireConfig memory cfg = _resolveConfig();

        require(cfg.ccipRouter != address(0), "RewireCCIP: router missing");
        require(cfg.gateway != address(0), "RewireCCIP: gateway missing");
        require(cfg.vault != address(0), "RewireCCIP: vault missing");
        require(cfg.swapper != address(0), "RewireCCIP: swapper missing");
        require(cfg.senderToKeep != address(0), "RewireCCIP: sender missing");
        require(bytes(cfg.destCaip2).length > 0, "RewireCCIP: destCaip2 missing");
        require(cfg.sourceSelector > 0, "RewireCCIP: source selector missing");
        require(cfg.sourceTrustedSender != address(0), "RewireCCIP: trusted sender missing");

        vm.startBroadcast(pk);

        CCIPReceiverAdapter newReceiver = new CCIPReceiverAdapter(cfg.ccipRouter, cfg.gateway);
        newReceiver.setSwapper(cfg.swapper);
        newReceiver.setTrustedSender(cfg.sourceSelector, abi.encode(cfg.sourceTrustedSender));

        IVaultCCIPRewire(cfg.vault).setAuthorizedSpender(address(newReceiver), true);
        IGatewayCCIPRewire(cfg.gateway).setAuthorizedAdapter(address(newReceiver), true);
        ISwapperCCIPRewire(cfg.swapper).setAuthorizedCaller(address(newReceiver), true);

        ICCIPSenderRewire(cfg.senderToKeep).setDestinationAdapter(cfg.destCaip2, abi.encode(address(newReceiver)));
        if (cfg.updateGasLimit) {
            ICCIPSenderRewire(cfg.senderToKeep).setDestinationGasLimit(cfg.destCaip2, cfg.destGasLimit);
        }
        if (cfg.updateExtraArgs) {
            ICCIPSenderRewire(cfg.senderToKeep).setDestinationExtraArgs(cfg.destCaip2, cfg.destExtraArgs);
        }

        if (cfg.deauthorizeOld && cfg.oldReceiver != address(0)) {
            IGatewayCCIPRewire(cfg.gateway).setAuthorizedAdapter(cfg.oldReceiver, false);
            IVaultCCIPRewire(cfg.vault).setAuthorizedSpender(cfg.oldReceiver, false);
            ISwapperCCIPRewire(cfg.swapper).setAuthorizedCaller(cfg.oldReceiver, false);
        }

        vm.stopBroadcast();

        require(IVaultCCIPRewire(cfg.vault).authorizedSpenders(address(newReceiver)), "RewireCCIP: vault auth missing");

        bytes memory trusted = ICCIPReceiverViewRewire(address(newReceiver)).trustedSenders(cfg.sourceSelector);
        require(keccak256(trusted) == keccak256(abi.encode(cfg.sourceTrustedSender)), "RewireCCIP: trusted sender mismatch");
        require(ICCIPReceiverViewRewire(address(newReceiver)).allowedSourceChains(cfg.sourceSelector), "RewireCCIP: source not allowed");

        bytes memory destAdapter = ICCIPSenderRewire(cfg.senderToKeep).destinationAdapters(cfg.destCaip2);
        require(keccak256(destAdapter) == keccak256(abi.encode(address(newReceiver))), "RewireCCIP: destination adapter mismatch");
        if (cfg.updateGasLimit) {
            require(
                ICCIPSenderRewire(cfg.senderToKeep).destinationGasLimits(cfg.destCaip2) == cfg.destGasLimit,
                "RewireCCIP: gas limit mismatch"
            );
        }

        console.log("RewireCCIPReceiverOnly complete");
        console.log("New receiver:", address(newReceiver));
        console.log("Sender kept:", cfg.senderToKeep);
        console.log("Dest CAIP2:", cfg.destCaip2);
        console.log("Source selector:", uint256(cfg.sourceSelector));
    }

    function _resolveConfig() internal returns (RewireConfig memory cfg) {
        string memory profile = vm.envOr("CCIP_REWIRE_PROFILE", string("auto"));

        if (_eq(profile, "base") || (_eq(profile, "auto") && block.chainid == 8453)) {
            cfg = RewireConfig({
                ccipRouter: vm.envOr("CCIP_REWIRE_CCIP_ROUTER", CCIP_ROUTER_BASE),
                gateway: vm.envOr("CCIP_REWIRE_GATEWAY", address(0x08409b0fa63b0bCEb4c4B49DBf286ff943b60011)),
                vault: vm.envOr("CCIP_REWIRE_VAULT", address(0x67d0af7f163F45578679eDa4BDf9042E3E5FEc60)),
                swapper: vm.envOr("CCIP_REWIRE_SWAPPER", address(0x8B6c7770D4B8AaD2d600e0cf5df3Eea5Bc0EB0fe)),
                senderToKeep: vm.envOr("CCIP_REWIRE_SENDER", address(0x47FEA6C20aC5F029BAB99Ec2ed756d94c54707DE)),
                oldReceiver: vm.envOr("CCIP_REWIRE_OLD_RECEIVER", address(0x46FAc7ac7D89d2daE0B647F31888AdD01cEed2bb)),
                destCaip2: vm.envOr("CCIP_REWIRE_DEST_CAIP2", string("eip155:42161")),
                sourceSelector: uint64(vm.envOr("CCIP_REWIRE_SOURCE_SELECTOR", uint256(SELECTOR_ARBITRUM))),
                sourceTrustedSender: vm.envOr("CCIP_REWIRE_SOURCE_TRUSTED_SENDER", address(0x5CCe8CdFb77dcCd28ed7Cf0aCf567F92d737ABd9)),
                destGasLimit: vm.envOr("CCIP_REWIRE_DEST_GAS_LIMIT", uint256(200000)),
                destExtraArgs: _parseBytesOrEmpty(vm.envOr("CCIP_REWIRE_DEST_EXTRA_ARGS_HEX", string(""))),
                updateGasLimit: vm.envOr("CCIP_REWIRE_UPDATE_GAS_LIMIT", false),
                updateExtraArgs: vm.envOr("CCIP_REWIRE_UPDATE_EXTRA_ARGS", false),
                deauthorizeOld: vm.envOr("CCIP_REWIRE_DEAUTHORIZE_OLD", false)
            });
        } else if (_eq(profile, "arbitrum") || (_eq(profile, "auto") && block.chainid == 42161)) {
            cfg = RewireConfig({
                ccipRouter: vm.envOr("CCIP_REWIRE_CCIP_ROUTER", CCIP_ROUTER_ARBITRUM),
                gateway: vm.envOr("CCIP_REWIRE_GATEWAY", address(0x259294aecdC0006B73b1281c30440A8179CFF44c)),
                vault: vm.envOr("CCIP_REWIRE_VAULT", address(0x4a92d4079853c78dF38B4BbD574AA88679Adef93)),
                swapper: vm.envOr("CCIP_REWIRE_SWAPPER", address(0x5d86BFd5a361bc652Bc596Dd2a77cD2bDBA2bf35)),
                senderToKeep: vm.envOr("CCIP_REWIRE_SENDER", address(0x5CCe8CdFb77dcCd28ed7Cf0aCf567F92d737ABd9)),
                oldReceiver: vm.envOr("CCIP_REWIRE_OLD_RECEIVER", address(0x0078f08C7A1c3daB5986F00Dc4E32018a95Ee195)),
                destCaip2: vm.envOr("CCIP_REWIRE_DEST_CAIP2", string("eip155:8453")),
                sourceSelector: uint64(vm.envOr("CCIP_REWIRE_SOURCE_SELECTOR", uint256(SELECTOR_BASE))),
                sourceTrustedSender: vm.envOr("CCIP_REWIRE_SOURCE_TRUSTED_SENDER", address(0x47FEA6C20aC5F029BAB99Ec2ed756d94c54707DE)),
                destGasLimit: vm.envOr("CCIP_REWIRE_DEST_GAS_LIMIT", uint256(200000)),
                destExtraArgs: _parseBytesOrEmpty(vm.envOr("CCIP_REWIRE_DEST_EXTRA_ARGS_HEX", string(""))),
                updateGasLimit: vm.envOr("CCIP_REWIRE_UPDATE_GAS_LIMIT", false),
                updateExtraArgs: vm.envOr("CCIP_REWIRE_UPDATE_EXTRA_ARGS", false),
                deauthorizeOld: vm.envOr("CCIP_REWIRE_DEAUTHORIZE_OLD", false)
            });
        } else {
            revert("RewireCCIP: unsupported profile");
        }
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function _parseBytesOrEmpty(string memory hexString) internal pure returns (bytes memory) {
        bytes memory raw = bytes(hexString);
        if (raw.length == 0) {
            return bytes("");
        }

        uint256 offset = 0;
        if (raw.length >= 2 && raw[0] == "0" && (raw[1] == "x" || raw[1] == "X")) {
            offset = 2;
        }

        require((raw.length - offset) % 2 == 0, "RewireCCIP: invalid hex length");

        bytes memory out = new bytes((raw.length - offset) / 2);
        for (uint256 i = 0; i < out.length; i++) {
            out[i] = bytes1((_fromHex(raw[offset + 2 * i]) << 4) | _fromHex(raw[offset + 2 * i + 1]));
        }
        return out;
    }

    function _fromHex(bytes1 c) internal pure returns (uint8) {
        uint8 b = uint8(c);
        if (b >= 48 && b <= 57) return b - 48;
        if (b >= 65 && b <= 70) return b - 55;
        if (b >= 97 && b <= 102) return b - 87;
        revert("RewireCCIP: invalid hex char");
    }
}
