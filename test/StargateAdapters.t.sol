// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/integrations/stargate/StargateSenderAdapter.sol";
import "../src/integrations/stargate/StargateReceiverAdapter.sol";
import "../src/vaults/PaymentKitaVault.sol";

contract MockStargateToken is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockStargatePrivacyGateway {
    mapping(bytes32 => address) public privacyStealthByPayment;
    mapping(bytes32 => address) public privacyFinalReceiverByPayment;
    mapping(bytes32 => bytes32) public privacyIntentByPayment;

    bytes32 public lastFinalizePaymentId;
    address public lastFinalizeReceiver;
    address public lastFinalizeToken;
    uint256 public lastFinalizeAmount;
    bytes32 public registeredPaymentId;
    bytes32 public registeredIntentId;
    address public registeredStealthReceiver;
    address public registeredFinalReceiver;
    address public registeredSourceSender;
    uint256 public finalizePrivacyCount;
    uint256 public reportPrivacyFailureCount;

    function setPrivacy(
        bytes32 paymentId,
        bytes32 intentId,
        address stealthReceiver,
        address finalReceiver
    ) external {
        privacyIntentByPayment[paymentId] = intentId;
        privacyStealthByPayment[paymentId] = stealthReceiver;
        privacyFinalReceiverByPayment[paymentId] = finalReceiver;
    }

    function registerIncomingPrivacyContext(
        bytes32 paymentId,
        bytes32 intentId,
        address stealthReceiver,
        address finalReceiver,
        address sourceSender
    ) external {
        registeredPaymentId = paymentId;
        registeredIntentId = intentId;
        registeredStealthReceiver = stealthReceiver;
        registeredFinalReceiver = finalReceiver;
        registeredSourceSender = sourceSender;
        privacyStealthByPayment[paymentId] = stealthReceiver;
    }

    function finalizeIncomingPayment(bytes32 paymentId, address receiver, address token, uint256 amount) external {
        lastFinalizePaymentId = paymentId;
        lastFinalizeReceiver = receiver;
        lastFinalizeToken = token;
        lastFinalizeAmount = amount;
    }

    function finalizePrivacyForward(bytes32, address, uint256) external {
        finalizePrivacyCount += 1;
    }

    function reportPrivacyForwardFailure(bytes32, string calldata) external {
        reportPrivacyFailureCount += 1;
    }
}

contract MockStargateSwapper {
    address public expectedTokenIn;
    address public expectedTokenOut;
    uint256 public expectedAmountIn;
    uint256 public expectedMinAmountOut;
    address public expectedRecipient;
    uint256 public amountOutToReturn;

    function setAmountOutToReturn(uint256 amountOut) external {
        amountOutToReturn = amountOut;
    }

    function swapFromVault(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external returns (uint256 amountOut) {
        expectedTokenIn = tokenIn;
        expectedTokenOut = tokenOut;
        expectedAmountIn = amountIn;
        expectedMinAmountOut = minAmountOut;
        expectedRecipient = recipient;
        amountOut = amountOutToReturn;
        bool ok = ERC20(tokenOut).transfer(recipient, amountOut);
        require(ok, "dest transfer failed");
    }
}

contract MockStargatePool {
    address public immutable tokenAddress;
    bytes32 public lastTo;
    uint32 public lastDstEid;
    uint256 public lastAmountLd;
    uint256 public lastMinAmountLd;
    bytes public lastComposeMsg;
    bytes public lastExtraOptions;
    address public lastRefundAddress;
    uint256 public quoteNativeFee = 0.0002 ether;
    uint256 public quoteAmountReceivedLd;
    bytes32 public nextGuid = keccak256("stargate-guid");

    constructor(address _token) {
        tokenAddress = _token;
    }

    function token() external view returns (address) {
        return tokenAddress;
    }

    function setQuoteAmountReceivedLd(uint256 amountReceivedLd) external {
        quoteAmountReceivedLd = amountReceivedLd;
    }

    function quoteOFT(
        IStargate.SendParam calldata sendParam
    )
        external
        view
        returns (IStargate.OFTLimit memory limit, IStargate.OFTFeeDetail[] memory feeDetails, IStargate.OFTReceipt memory receipt)
    {
        limit = IStargate.OFTLimit({minAmountLD: 1, maxAmountLD: type(uint256).max});
        feeDetails = new IStargate.OFTFeeDetail[](0);
        receipt = IStargate.OFTReceipt({
            amountSentLD: sendParam.amountLD,
            amountReceivedLD: quoteAmountReceivedLd == 0 ? sendParam.amountLD : quoteAmountReceivedLd
        });
    }

    function quoteSend(
        IStargate.SendParam calldata,
        bool
    ) external view returns (IStargate.MessagingFee memory fee) {
        fee = IStargate.MessagingFee({nativeFee: quoteNativeFee, lzTokenFee: 0});
    }

    function sendToken(
        IStargate.SendParam calldata sendParam,
        IStargate.MessagingFee calldata fee,
        address refundAddress
    )
        external
        payable
        returns (IStargate.MessagingReceipt memory msgReceipt, IStargate.OFTReceipt memory oftReceipt, IStargate.Ticket memory ticket)
    {
        lastTo = sendParam.to;
        lastDstEid = sendParam.dstEid;
        lastAmountLd = sendParam.amountLD;
        lastMinAmountLd = sendParam.minAmountLD;
        lastComposeMsg = sendParam.composeMsg;
        lastExtraOptions = sendParam.extraOptions;
        lastRefundAddress = refundAddress;

        msgReceipt = IStargate.MessagingReceipt({
            guid: nextGuid,
            nonce: 1,
            fee: IStargate.MessagingFee({nativeFee: fee.nativeFee, lzTokenFee: fee.lzTokenFee})
        });
        oftReceipt = IStargate.OFTReceipt({
            amountSentLD: sendParam.amountLD,
            amountReceivedLD: sendParam.minAmountLD
        });
        ticket = IStargate.Ticket({ticketId: 0, passenger: bytes("")});
    }
}

contract StargateAdaptersTest is Test {
    uint8 constant PAYLOAD_VERSION_V1 = 1;
    uint32 constant SRC_EID = 30184;
    uint32 constant DST_EID = 30109;

    MockStargateToken usdc;
    MockStargateToken dstToken;
    PaymentKitaVault vault;
    MockStargatePrivacyGateway gateway;
    MockStargateSwapper swapper;
    MockStargatePool stargate;
    StargateSenderAdapter sender;
    StargateReceiverAdapter receiver;

    address router = address(0xBEEF);
    address endpoint = address(0x1001);
    address localStargate = address(0x2002);
    address receiverUser = address(0xA11CE);
    address finalReceiver = address(0xB0B);

    function setUp() public {
        usdc = new MockStargateToken("USDC", "USDC");
        dstToken = new MockStargateToken("Destination", "DST");
        vault = new PaymentKitaVault();
        gateway = new MockStargatePrivacyGateway();
        swapper = new MockStargateSwapper();
        stargate = new MockStargatePool(address(usdc));

        sender = new StargateSenderAdapter(address(vault), address(gateway), router);
        receiver = new StargateReceiverAdapter(endpoint, address(gateway), address(vault));
        receiver.setSwapper(address(swapper));

        vm.deal(router, 1 ether);

        sender.setRoute("eip155:137", address(stargate), DST_EID, bytes32(uint256(uint160(address(receiver)))));
        receiver.setRoute(SRC_EID, localStargate, address(usdc));

        vault.setAuthorizedSpender(address(sender), true);
        vault.setAuthorizedSpender(address(receiver), true);
        vault.setAuthorizedSpender(address(swapper), true);

        usdc.mint(address(vault), 1_000_000e6);
        dstToken.mint(address(swapper), 1_000_000e6);
        stargate.setQuoteAmountReceivedLd(95e6);
    }

    function testStargateSenderSendMessageBuildsComposedRoute() public {
        bytes32 paymentId = keccak256("stargate-regular");
        IBridgeAdapter.BridgeMessage memory message = IBridgeAdapter.BridgeMessage({
            paymentId: paymentId,
            receiver: receiverUser,
            sourceToken: address(usdc),
            destToken: address(usdc),
            amount: 100e6,
            destChainId: "eip155:137",
            minAmountOut: 90e6,
            payer: address(this)
        });

        vm.prank(router);
        bytes32 guid = sender.sendMessage{value: 0.0002 ether}(message);

        assertEq(guid, stargate.nextGuid());
        assertEq(stargate.lastDstEid(), DST_EID);
        assertEq(stargate.lastAmountLd(), 100e6);
        assertEq(stargate.lastMinAmountLd(), 95e6);
        assertEq(stargate.lastRefundAddress(), address(this));
        (
            uint8 version,
            bytes32 decodedPaymentId,
            address decodedReceiver,
            address decodedDestToken,
            uint256 decodedMinAmountOut,
            bool isPrivacy,
            bytes32 decodedIntentId,
            address decodedStealth,
            address decodedFinalReceiver,
            address decodedPayer
        ) = abi.decode(stargate.lastComposeMsg(), (uint8, bytes32, address, address, uint256, bool, bytes32, address, address, address));
        assertEq(version, PAYLOAD_VERSION_V1);
        assertEq(decodedPaymentId, paymentId);
        assertEq(decodedReceiver, receiverUser);
        assertEq(decodedDestToken, address(usdc));
        assertEq(decodedMinAmountOut, 90e6);
        assertEq(isPrivacy, false);
        assertEq(decodedIntentId, bytes32(0));
        assertEq(decodedStealth, address(0));
        assertEq(decodedFinalReceiver, address(0));
        assertEq(decodedPayer, address(this));
    }

    function testStargateReceiverRegularDirectSettlement() public {
        bytes32 paymentId = keccak256("stargate-direct");
        uint256 amountLd = 100e6;
        usdc.mint(address(receiver), amountLd);

        bytes memory appPayload = abi.encode(
            PAYLOAD_VERSION_V1,
            paymentId,
            receiverUser,
            address(usdc),
            95e6,
            false,
            bytes32(0),
            address(0),
            address(0),
            address(this)
        );
        bytes memory message = abi.encodePacked(
            uint64(1),
            SRC_EID,
            amountLd,
            bytes32(uint256(uint160(address(this)))),
            appPayload
        );

        vm.prank(endpoint);
        receiver.lzCompose(localStargate, keccak256("guid-1"), message, address(0), bytes(""));

        assertEq(usdc.balanceOf(receiverUser), amountLd);
        assertEq(gateway.lastFinalizePaymentId(), paymentId);
        assertEq(gateway.lastFinalizeToken(), address(usdc));
        assertEq(gateway.lastFinalizeAmount(), amountLd);
    }

    function testStargateReceiverPrivacyRegistersContextAndSwaps() public {
        bytes32 paymentId = keccak256("stargate-privacy");
        bytes32 intentId = keccak256("intent");
        uint256 amountLd = 100e6;
        address stealth = receiverUser;
        gateway.setPrivacy(paymentId, intentId, stealth, finalReceiver);
        swapper.setAmountOutToReturn(97e6);
        usdc.mint(address(receiver), amountLd);

        bytes memory appPayload = abi.encode(
            PAYLOAD_VERSION_V1,
            paymentId,
            stealth,
            address(dstToken),
            96e6,
            true,
            intentId,
            stealth,
            finalReceiver,
            address(this)
        );
        bytes memory message = abi.encodePacked(
            uint64(2),
            SRC_EID,
            amountLd,
            bytes32(uint256(uint160(address(this)))),
            appPayload
        );

        vm.prank(endpoint);
        receiver.lzCompose(localStargate, keccak256("guid-2"), message, address(0), bytes(""));

        assertEq(gateway.registeredPaymentId(), paymentId);
        assertEq(gateway.registeredIntentId(), intentId);
        assertEq(gateway.registeredFinalReceiver(), finalReceiver);
        assertEq(dstToken.balanceOf(stealth), 97e6);
        assertEq(gateway.lastFinalizePaymentId(), paymentId);
        assertEq(gateway.lastFinalizeToken(), address(dstToken));
        assertEq(gateway.lastFinalizeAmount(), 97e6);
        assertEq(gateway.finalizePrivacyCount(), 1);
    }

    function testStargateReceiverAcceptsLegacyPrefixedComposePayload() public {
        bytes32 paymentId = keccak256("stargate-legacy-prefix");
        uint256 amountLd = 100e6;
        usdc.mint(address(receiver), amountLd);

        bytes memory appPayload = abi.encode(
            PAYLOAD_VERSION_V1,
            paymentId,
            receiverUser,
            address(usdc),
            95e6,
            false,
            bytes32(0),
            address(0),
            address(0),
            address(this)
        );
        bytes memory message = abi.encodePacked(
            uint64(3),
            SRC_EID,
            amountLd,
            bytes32(uint256(uint160(address(sender)))),
            bytes32(uint256(uint160(address(this)))),
            appPayload
        );

        vm.prank(endpoint);
        receiver.lzCompose(localStargate, keccak256("guid-legacy"), message, address(0), bytes(""));

        assertEq(usdc.balanceOf(receiverUser), amountLd);
        assertEq(gateway.lastFinalizePaymentId(), paymentId);
        assertEq(gateway.lastFinalizeToken(), address(usdc));
        assertEq(gateway.lastFinalizeAmount(), amountLd);
    }

    function testRescueTokenTransfersToRecipient() public {
        uint256 rescueAmount = 50e6;
        usdc.mint(address(receiver), rescueAmount);
        
        uint256 initialBalance = usdc.balanceOf(receiverUser);
        
        // address(this) is the owner since it deployed `receiver`
        receiver.rescueToken(IERC20(address(usdc)), receiverUser, rescueAmount);
        
        assertEq(usdc.balanceOf(receiverUser), initialBalance + rescueAmount);
        assertEq(usdc.balanceOf(address(receiver)), 0);
    }

    function testRescueTokenRevertsForNonOwner() public {
        uint256 rescueAmount = 50e6;
        usdc.mint(address(receiver), rescueAmount);
        
        vm.prank(address(0xBAD));
        vm.expectRevert();
        receiver.rescueToken(IERC20(address(usdc)), receiverUser, rescueAmount);
    }

    function testRescueNativeTransfersToRecipient() public {
        uint256 rescueAmount = 1 ether;
        vm.deal(address(receiver), rescueAmount);
        
        uint256 initialBalance = receiverUser.balance;
        
        receiver.rescueNative(payable(receiverUser), rescueAmount);
        
        assertEq(receiverUser.balance, initialBalance + rescueAmount);
        assertEq(address(receiver).balance, 0);
    }
}
