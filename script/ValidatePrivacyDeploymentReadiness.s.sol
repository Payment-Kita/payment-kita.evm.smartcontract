// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/interfaces/IPaymentKitaGateway.sol";

interface IPrivacyGateGateway is IPaymentKitaGateway {
    function validatorModule() external view returns (address);
    function quoteModule() external view returns (address);
    function executionModule() external view returns (address);
    function privacyModule() external view returns (address);
    function feePolicyManager() external view returns (address);
    function isAuthorizedAdapter(address adapter) external view returns (bool);
    function privacyForwardCompleted(bytes32 paymentId) external view returns (bool);
    function privacyForwardRetryCount(bytes32 paymentId) external view returns (uint8);
}

interface IPrivacyGateVault {
    function authorizedSpenders(address spender) external view returns (bool);
}

interface IPrivacyGateSwapper {
    function authorizedCallers(address caller) external view returns (bool);
}

interface IPrivacyGateModule {
    function authorizedGateway(address gateway) external view returns (bool);
}

interface IPrivacyEscrowFactoryGate {
    function predictEscrow(bytes32 salt, address owner, address forwarder) external view returns (address);
}

interface IPrivacyEscrowGate {
    function owner() external view returns (address);
    function forwarder() external view returns (address);
}

contract ValidatePrivacyDeploymentReadiness is Script {
    function run() external {
        address gatewayAddr = vm.envAddress("PRIVACY_GATE_GATEWAY");
        address vaultAddr = vm.envAddress("PRIVACY_GATE_VAULT");
        address swapperAddr = vm.envAddress("PRIVACY_GATE_SWAPPER");
        address expectedPrivacyModule = vm.envOr("PRIVACY_GATE_PRIVACY_MODULE", address(0));

        address ccipReceiver = vm.envOr("PRIVACY_GATE_ADAPTER_CCIP", address(0));
        address hyperbridgeReceiver = vm.envOr("PRIVACY_GATE_ADAPTER_HYPERBRIDGE", address(0));
        address layerzeroReceiver = vm.envOr("PRIVACY_GATE_ADAPTER_LAYERZERO", address(0));

        address sourceToken = vm.envOr("PRIVACY_GATE_SOURCE_TOKEN", address(0));
        address destToken = vm.envOr("PRIVACY_GATE_DEST_TOKEN", address(0));
        string memory destCaip2 = vm.envOr("PRIVACY_GATE_DEST_CAIP2", string(""));
        address receiver = vm.envOr("PRIVACY_GATE_RECEIVER", address(0));
        uint256 amount = vm.envOr("PRIVACY_GATE_AMOUNT", uint256(0));
        address escrowFactory = vm.envOr("PRIVACY_GATE_ESCROW_FACTORY", address(0));
        address expectedStealthEscrow = vm.envOr("PRIVACY_GATE_EXPECTED_STEALTH_ESCROW", address(0));
        uint256 escrowSaltRaw = vm.envOr("PRIVACY_GATE_ESCROW_SALT_UINT", uint256(0));

        IPrivacyGateGateway gateway = IPrivacyGateGateway(gatewayAddr);
        IPrivacyGateVault vault = IPrivacyGateVault(vaultAddr);
        IPrivacyGateSwapper swapper = IPrivacyGateSwapper(swapperAddr);

        address validator = gateway.validatorModule();
        address quoter = gateway.quoteModule();
        address executor = gateway.executionModule();
        address privacy = gateway.privacyModule();
        address feePolicyManager = gateway.feePolicyManager();

        require(validator != address(0), "PRIVACY GATE FAIL: validator module missing");
        require(quoter != address(0), "PRIVACY GATE FAIL: quote module missing");
        require(executor != address(0), "PRIVACY GATE FAIL: execution module missing");
        require(privacy != address(0), "PRIVACY GATE FAIL: privacy module missing");
        require(feePolicyManager != address(0), "PRIVACY GATE FAIL: fee policy manager missing");
        if (expectedPrivacyModule != address(0)) {
            require(privacy == expectedPrivacyModule, "PRIVACY GATE FAIL: privacy module mismatch");
        }

        require(IPrivacyGateModule(privacy).authorizedGateway(gatewayAddr), "PRIVACY GATE FAIL: gateway not authorized in privacy module");
        require(vault.authorizedSpenders(gatewayAddr), "PRIVACY GATE FAIL: vault missing gateway authorization");
        require(vault.authorizedSpenders(swapperAddr), "PRIVACY GATE FAIL: vault missing swapper authorization");
        require(swapper.authorizedCallers(gatewayAddr), "PRIVACY GATE FAIL: swapper missing gateway authorization");
        require(!gateway.privacyForwardCompleted(bytes32(0)), "PRIVACY GATE FAIL: privacy forward probe should be false");
        require(gateway.privacyForwardRetryCount(bytes32(0)) == 0, "PRIVACY GATE FAIL: privacy retry probe should be zero");

        _assertAdapter(gateway, vault, swapper, ccipReceiver, "CCIP receiver");
        _assertAdapter(gateway, vault, swapper, hyperbridgeReceiver, "Hyperbridge receiver");
        _assertAdapter(gateway, vault, swapper, layerzeroReceiver, "LayerZero receiver");

        address forwardExecutor = vm.envOr("PRIVACY_GATE_FORWARD_EXECUTOR", privacy);
        address escrowOwner = vm.envOr("PRIVACY_GATE_ESCROW_OWNER", receiver == address(0) ? gatewayAddr : receiver);
        if (escrowFactory != address(0)) {
            require(escrowFactory.code.length > 0, "PRIVACY GATE FAIL: escrow factory has no code");
            bytes32 salt =
                escrowSaltRaw == 0
                    ? keccak256(abi.encodePacked("privacy-v2-gate", gatewayAddr, escrowOwner, forwardExecutor))
                    : bytes32(escrowSaltRaw);
            address predicted = IPrivacyEscrowFactoryGate(escrowFactory).predictEscrow(salt, escrowOwner, forwardExecutor);
            require(predicted != address(0), "PRIVACY GATE FAIL: invalid escrow prediction");

            if (expectedStealthEscrow != address(0)) {
                require(predicted == expectedStealthEscrow, "PRIVACY GATE FAIL: predicted escrow mismatch");
                require(expectedStealthEscrow.code.length > 0, "PRIVACY GATE FAIL: expected escrow not deployed");
                require(IPrivacyEscrowGate(expectedStealthEscrow).forwarder() == forwardExecutor, "PRIVACY GATE FAIL: escrow forwarder mismatch");
            }

            console.log("[PASS] escrow factory probe");
            console.log("escrowFactory:", escrowFactory);
            console.log("escrowForwardExecutor:", forwardExecutor);
            console.log("escrowPredicted:", predicted);
        }

        bool runQuoteProbe =
            sourceToken != address(0) &&
            destToken != address(0) &&
            bytes(destCaip2).length > 0 &&
            receiver != address(0) &&
            amount > 0;

        if (runQuoteProbe) {
            IPaymentKitaGateway.PaymentRequestV2 memory req;
            req.destChainIdBytes = bytes(destCaip2);
            req.receiverBytes = abi.encode(receiver);
            req.sourceToken = sourceToken;
            req.bridgeTokenSource = address(0);
            req.destToken = destToken;
            req.amountInSource = amount;
            req.minBridgeAmountOut = 0;
            req.minDestAmountOut = 0;
            req.mode = IPaymentKitaGateway.PaymentMode.PRIVACY;
            req.bridgeOption = 255;

            (
                uint256 platformFee,
                uint256 bridgeFeeNative,
                uint256 totalSourceTokenRequired,
                uint8 bridgeType,
                bool bridgeQuoteOk,
                string memory bridgeQuoteReason
            ) = gateway.quotePaymentCost(req);

            (address approvalToken, uint256 approvalAmount, uint256 requiredNativeFee) = gateway.previewApproval(req);

            console.log("[PASS] privacy quote probe");
            console.log("platformFee");
            console.log(platformFee);
            console.log("bridgeFeeNative");
            console.log(bridgeFeeNative);
            console.log("totalSourceTokenRequired");
            console.log(totalSourceTokenRequired);
            console.log("bridgeType");
            console.log(uint256(bridgeType));
            console.log("bridgeQuoteOk:", bridgeQuoteOk);
            console.log("bridgeQuoteReason:", bridgeQuoteReason);
            console.log("approvalToken:", approvalToken);
            console.log("approvalAmount");
            console.log(approvalAmount);
            console.log("requiredNativeFee");
            console.log(requiredNativeFee);
        } else {
            console.log("[SKIP] privacy quote probe (set PRIVACY_GATE_SOURCE_TOKEN, PRIVACY_GATE_DEST_TOKEN, PRIVACY_GATE_DEST_CAIP2, PRIVACY_GATE_RECEIVER, PRIVACY_GATE_AMOUNT)");
        }

        console.log("[PASS] privacy deployment readiness gate");
        console.log("gateway:", gatewayAddr);
        console.log("vault:", vaultAddr);
        console.log("swapper:", swapperAddr);
        console.log("privacyModule:", privacy);
        console.log("forwardExecutor:", forwardExecutor);
    }

    function _assertAdapter(
        IPrivacyGateGateway gateway,
        IPrivacyGateVault vault,
        IPrivacyGateSwapper swapper,
        address adapter,
        string memory label
    ) internal view {
        if (adapter == address(0)) return;
        require(gateway.isAuthorizedAdapter(adapter), string.concat("PRIVACY GATE FAIL: gateway missing adapter authorization for ", label));
        require(vault.authorizedSpenders(adapter), string.concat("PRIVACY GATE FAIL: vault missing spender authorization for ", label));
        require(swapper.authorizedCallers(adapter), string.concat("PRIVACY GATE FAIL: swapper missing caller authorization for ", label));
        console.log("[PASS] adapter authorization:", label);
    }
}
