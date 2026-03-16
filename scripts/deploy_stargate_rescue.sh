#!/bin/bash
set -a
source .env
set +a

# Defaults (Example for Base)
export RPC_URL=${BASE_RPC_URL}
export GATEWAY_CONTRACT="0x08409b0fa63b0bCEb4c4B49DBf286ff943b60011"
export VAULT_CONTRACT="0x67d0af7f163F45578679eDa4BDf9042E3E5FEc60"
export SWAPPER_CONTRACT="0x8B6c7770D4B8AaD2d600e0cf5df3Eea5Bc0EB0fe"
export LAYERZERO_ENDPOINT="0x1a44076050125825900e736c501f859c50fE728c" # Base Endpoint V2
export STARGATE_SRC_EID=30109 # Polygon
export TRUSTED_STARGATE_POOL="0x9Aa02D4Fae7F58b8E8f34c66E756cC734DAc7fe4" # Polygon USDC Pool
export RECEIVED_TOKEN="0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913" # Base USDC
export OLD_RECEIVER="0x26C277f9ce9649637BfC325Bce3fA83a60921A5A" # The current stuck receiver on Base

echo "========================================================"
echo "Deploying and Wire Rescuable StargateReceiverAdapter"
echo "========================================================"

forge script script/DeployStargateRescuableReceiver.s.sol:DeployStargateRescuableReceiver \
    --rpc-url $RPC_URL \
    --broadcast \
    --verify \
    --etherscan-api-key $BASESCAN_API_KEY \
    -vvvv

echo "========================================================"
echo "Deployment & Verification Complete!"
echo "========================================================"
echo ""
echo "Next Steps for Recovery (lzComposeRetry):"
echo "1. Obtain the message payload from the stuck transaction."
echo "2. The LZ Endpoint might allow re-triggering the message via lzCompose / clear."
echo "3. However, since the receiver address is hardcoded in the original message's destination adapter field,"
echo "   you cannot reroute the existing stuck message to the NEW receiver contract."
echo "4. Resolution: The funds stuck in the OLD receiver MUST be rescued by upgrading the OLD receiver (if it is a proxy)."
echo "   If the OLD receiver is NOT a proxy, the stuck USDC is permanently locked in the OLD adapter context."
echo "========================================================"
