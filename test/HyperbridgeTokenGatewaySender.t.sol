// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ITokenGateway, TeleportParams, TokenGatewayParams} from "@hyperbridge/core/apps/TokenGateway.sol";
import "../src/interfaces/IBridgeAdapter.sol";
import "../src/vaults/PaymentKitaVault.sol";
import "../src/integrations/hyperbridge/HyperbridgeTokenGatewaySender.sol";

contract MockBridgeToken is ERC20 {
    constructor() ERC20("BridgeToken", "BRDG") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockTokenGateway is ITokenGateway {
    mapping(bytes32 => address) public erc20Map;
    mapping(bytes32 => address) public erc6160Map;
    mapping(bytes32 => address) public instanceMap;

    uint256 public lastAmount;
    uint256 public lastRelayerFee;
    bytes32 public lastAssetId;
    bool public lastRedeem;
    bytes32 public lastTo;
    bytes public lastDest;
    uint64 public lastTimeout;
    uint256 public lastNativeCost;
    bytes public lastData;
    uint256 public lastMsgValue;
    address public lastCaller;

    function setErc20(bytes32 assetId, address token) external {
        erc20Map[assetId] = token;
    }

    function setInstance(bytes calldata stateMachine, address instanceAddress) external {
        instanceMap[keccak256(stateMachine)] = instanceAddress;
    }

    function params() external pure override returns (TokenGatewayParams memory) {
        return TokenGatewayParams({host: address(0x1001), dispatcher: address(0x1002)});
    }

    function erc20(bytes32 assetId) external view override returns (address) {
        return erc20Map[assetId];
    }

    function erc6160(bytes32 assetId) external view override returns (address) {
        return erc6160Map[assetId];
    }

    function instance(bytes calldata destination) external view override returns (address) {
        return instanceMap[keccak256(destination)];
    }

    function teleport(TeleportParams calldata teleportParams) external payable override {
        address token = erc20Map[teleportParams.assetId];
        if (token == address(0)) revert UnknownAsset();

        lastAmount = teleportParams.amount;
        lastRelayerFee = teleportParams.relayerFee;
        lastAssetId = teleportParams.assetId;
        lastRedeem = teleportParams.redeem;
        lastTo = teleportParams.to;
        lastDest = teleportParams.dest;
        lastTimeout = teleportParams.timeout;
        lastNativeCost = teleportParams.nativeCost;
        lastData = teleportParams.data;
        lastMsgValue = msg.value;
        lastCaller = msg.sender;

        bool ok = ERC20(token).transferFrom(msg.sender, address(this), teleportParams.amount);
        require(ok, "transferFrom failed");
    }
}

contract MockPrivacyGatewayMetadata {
    mapping(bytes32 => address) public privacyStealthByPayment;
    mapping(bytes32 => address) public privacyFinalReceiverByPayment;
    mapping(bytes32 => bytes32) public privacyIntentByPayment;

    function setPrivacyContext(
        bytes32 paymentId,
        bytes32 intentId,
        address stealthReceiver,
        address finalReceiver
    ) external {
        privacyIntentByPayment[paymentId] = intentId;
        privacyStealthByPayment[paymentId] = stealthReceiver;
        privacyFinalReceiverByPayment[paymentId] = finalReceiver;
    }
}

contract HyperbridgeTokenGatewaySenderTest is Test {
    PaymentKitaVault vault;
    MockBridgeToken token;
    MockTokenGateway tokenGateway;
    MockPrivacyGatewayMetadata gatewayMetadata;
    HyperbridgeTokenGatewaySender sender;

    string constant DEST_CAIP2 = "eip155:137";
    bytes constant DEST_STATE_MACHINE = bytes("EVM-137");
    bytes32 constant USDC_ASSET_ID = keccak256("USDC");
    address constant REMOTE_GATEWAY = address(0xBEEF);
    address constant DEST_SETTLEMENT_EXECUTOR = address(0xF00D);

    function setUp() public {
        vault = new PaymentKitaVault();
        token = new MockBridgeToken();
        tokenGateway = new MockTokenGateway();
        gatewayMetadata = new MockPrivacyGatewayMetadata();
        sender = new HyperbridgeTokenGatewaySender(
            address(vault),
            address(tokenGateway),
            address(gatewayMetadata),
            address(this)
        );

        vault.setAuthorizedSpender(address(sender), true);

        sender.setStateMachineId(DEST_CAIP2, DEST_STATE_MACHINE);
        sender.setRouteSettlementExecutor(DEST_CAIP2, DEST_SETTLEMENT_EXECUTOR);
        sender.setNativeCost(DEST_CAIP2, 0.001 ether);
        sender.setRelayerFee(DEST_CAIP2, 123);
        sender.setTokenAssetId(address(token), USDC_ASSET_ID);

        tokenGateway.setErc20(USDC_ASSET_ID, address(token));
        tokenGateway.setInstance(DEST_STATE_MACHINE, REMOTE_GATEWAY);

        token.mint(address(vault), 1_000_000e6);
    }

    function _message(
        address srcToken,
        address dstToken,
        uint256 amount
    ) internal pure returns (IBridgeAdapter.BridgeMessage memory m) {
        m = IBridgeAdapter.BridgeMessage({
            paymentId: keccak256("payment-token-gateway"),
            receiver: address(0xA11CE),
            sourceToken: srcToken,
            destToken: dstToken,
            amount: amount,
            destChainId: DEST_CAIP2,
            minAmountOut: 0,
            payer: address(0xCAFE)
        });
    }

    function testIsRouteConfiguredTrueWhenStateMachineAndInstanceReady() public {
        assertTrue(sender.isRouteConfigured(DEST_CAIP2));
    }

    function testIsRouteConfiguredFalseWhenInstanceMissing() public {
        tokenGateway.setInstance(DEST_STATE_MACHINE, address(0));
        assertFalse(sender.isRouteConfigured(DEST_CAIP2));
    }

    function testIsRouteConfiguredFalseWhenSettlementExecutorMissing() public {
        sender.setRouteSettlementExecutor(DEST_CAIP2, address(0x1234));
        sender.setStateMachineId("eip155:10", DEST_STATE_MACHINE);
        assertFalse(sender.isRouteConfigured("eip155:10"));
    }

    function testQuoteFeeReturnsConfiguredNativeCost() public {
        IBridgeAdapter.BridgeMessage memory m = _message(address(token), address(token), 100e6);
        assertEq(sender.quoteFee(m), 0.001 ether);
    }

    function testSendMessageUsesRouteTimeoutWhenConfigured() public {
        sender.setRouteTimeout(DEST_CAIP2, 10_800);
        IBridgeAdapter.BridgeMessage memory m = _message(address(token), address(token), 100e6);

        sender.sendMessage{value: 0.001 ether}(m);

        assertEq(tokenGateway.lastTimeout(), 10_800);
    }

    function testSendMessageRevertsWhenCallerNotRouter() public {
        IBridgeAdapter.BridgeMessage memory m = _message(address(token), address(token), 100e6);

        vm.prank(address(0xDEAD));
        vm.expectRevert(HyperbridgeTokenGatewaySender.NotRouter.selector);
        sender.sendMessage(m);
    }

    function testSendMessageRevertsWhenSettlementExecutorMissing() public {
        sender.setStateMachineId("eip155:10", DEST_STATE_MACHINE);
        sender.setNativeCost("eip155:10", 0.001 ether);
        IBridgeAdapter.BridgeMessage memory m = _message(address(token), address(0xB0B), 100e6);
        m.destChainId = "eip155:10";

        vm.expectRevert(
            abi.encodeWithSelector(HyperbridgeTokenGatewaySender.SettlementExecutorNotConfigured.selector, "eip155:10")
        );
        sender.sendMessage{value: 0.001 ether}(m);
    }

    function testSendMessageRevertsWhenNativeFeeInsufficient() public {
        IBridgeAdapter.BridgeMessage memory m = _message(address(token), address(token), 100e6);

        vm.expectRevert(
            abi.encodeWithSelector(
                HyperbridgeTokenGatewaySender.InsufficientNativeFee.selector,
                0.001 ether,
                0.0005 ether
            )
        );
        sender.sendMessage{value: 0.0005 ether}(m);
    }

    function testSendMessagePullsFromVaultAndTeleports() public {
        uint256 amount = 250e6;
        IBridgeAdapter.BridgeMessage memory m = _message(address(token), address(0xB0B), amount);
        uint256 vaultBefore = token.balanceOf(address(vault));

        bytes32 messageId = sender.sendMessage{value: 0.001 ether}(m);
        assertTrue(messageId != bytes32(0));

        assertEq(token.balanceOf(address(vault)), vaultBefore - amount);
        assertEq(token.balanceOf(address(tokenGateway)), amount);
        assertEq(tokenGateway.lastAmount(), amount);
        assertEq(tokenGateway.lastRelayerFee(), 123);
        assertEq(tokenGateway.lastAssetId(), USDC_ASSET_ID);
        assertEq(tokenGateway.lastRedeem(), true);
        assertEq(tokenGateway.lastTo(), bytes32(uint256(uint160(DEST_SETTLEMENT_EXECUTOR))));
        assertEq(tokenGateway.lastTimeout(), sender.defaultTimeout());
        assertEq(tokenGateway.lastNativeCost(), 0.001 ether);
        assertEq(tokenGateway.lastMsgValue(), 0.001 ether);
        assertEq(tokenGateway.lastCaller(), address(sender));

        bytes memory data = tokenGateway.lastData();
        bytes4 selector;
        assembly {
            selector := mload(add(data, 32))
        }
        assertEq(selector, bytes4(keccak256("onTokenGatewayPayload(bytes)")));

        bytes memory encodedArg = new bytes(data.length - 4);
        for (uint256 i = 4; i < data.length; i++) {
            encodedArg[i - 4] = data[i];
        }
        bytes memory payload = abi.decode(encodedArg, (bytes));
        (
            uint8 version,
            bytes32 decodedPaymentId,
            address decodedReceiver,
            address decodedDestToken,
            uint256 decodedMinAmountOut,
            bytes32 decodedAssetId,
            uint256 decodedAmount,
            bool isPrivacy,
            bytes32 privacyIntentId,
            address privacyStealthReceiver,
            address privacyFinalReceiver,
            address sourceSender
        ) = abi.decode(payload, (uint8, bytes32, address, address, uint256, bytes32, uint256, bool, bytes32, address, address, address));
        assertEq(version, sender.PAYLOAD_VERSION_V2());
        assertEq(decodedPaymentId, m.paymentId);
        assertEq(decodedReceiver, m.receiver);
        assertEq(decodedDestToken, m.destToken);
        assertEq(decodedMinAmountOut, m.minAmountOut);
        assertEq(decodedAssetId, USDC_ASSET_ID);
        assertEq(decodedAmount, amount);
        assertFalse(isPrivacy);
        assertEq(privacyIntentId, bytes32(0));
        assertEq(privacyStealthReceiver, address(0));
        assertEq(privacyFinalReceiver, address(0));
        assertEq(sourceSender, m.payer);
    }

    function testGetRouteConfigIncludesRouteTimeoutAndEffectiveTimeout() public {
        sender.setRouteTimeout(DEST_CAIP2, 12_000);

        (bool configured, bytes memory configA, bytes memory configB) = sender.getRouteConfig(DEST_CAIP2);
        assertTrue(configured);
        assertEq(configA, DEST_STATE_MACHINE);

        (
            uint256 nativeCost,
            uint256 relayerFee,
            uint64 routeTimeout,
            uint64 effectiveTimeout,
            address remoteGateway,
            address settlementExecutor
        ) = abi.decode(configB, (uint256, uint256, uint64, uint64, address, address));

        assertEq(nativeCost, 0.001 ether);
        assertEq(relayerFee, 123);
        assertEq(routeTimeout, 12_000);
        assertEq(effectiveTimeout, 12_000);
        assertEq(remoteGateway, REMOTE_GATEWAY);
        assertEq(settlementExecutor, DEST_SETTLEMENT_EXECUTOR);
    }

    function testSendMessageEmbedsPrivacyContextWhenPaymentIsPrivate() public {
        uint256 amount = 100e6;
        IBridgeAdapter.BridgeMessage memory m = _message(address(token), address(0xB0B), amount);
        address stealth = m.receiver;
        address finalReceiver = address(0xBADA55);
        bytes32 intentId = keccak256("intent-v2");
        gatewayMetadata.setPrivacyContext(m.paymentId, intentId, stealth, finalReceiver);

        sender.sendMessage{value: 0.001 ether}(m);

        bytes memory data = tokenGateway.lastData();
        bytes memory encodedArg = new bytes(data.length - 4);
        for (uint256 i = 4; i < data.length; i++) {
            encodedArg[i - 4] = data[i];
        }
        bytes memory payload = abi.decode(encodedArg, (bytes));
        (
            uint8 version,
            ,
            ,
            ,
            ,
            ,
            ,
            bool isPrivacy,
            bytes32 decodedIntentId,
            address decodedStealth,
            address decodedFinalReceiver,
            address sourceSender
        ) = abi.decode(payload, (uint8, bytes32, address, address, uint256, bytes32, uint256, bool, bytes32, address, address, address));
        assertEq(version, sender.PAYLOAD_VERSION_V2());
        assertTrue(isPrivacy);
        assertEq(decodedIntentId, intentId);
        assertEq(decodedStealth, stealth);
        assertEq(decodedFinalReceiver, finalReceiver);
        assertEq(sourceSender, m.payer);
    }

    function testSendMessageRevertsWhenPrivacyStealthDoesNotMatchMessageReceiver() public {
        IBridgeAdapter.BridgeMessage memory m = _message(address(token), address(0xB0B), 100e6);
        gatewayMetadata.setPrivacyContext(m.paymentId, keccak256("intent"), address(0x1234), address(0x5678));

        vm.expectRevert(
            abi.encodeWithSelector(
                HyperbridgeTokenGatewaySender.PrivacyReceiverMismatch.selector,
                address(0x1234),
                m.receiver
            )
        );
        sender.sendMessage{value: 0.001 ether}(m);
    }
}
