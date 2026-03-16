#!/bin/bash
set -a
source .env
set +a

# Defaults for Arbitrum
export RPC_URL=${ARBITRUM_RPC_URL}
export GATEWAY_CONTRACT="0x259294aecdc0006b73b1281c30440a8179cff44c"
export VAULT_CONTRACT="0x4a92d4079853c78df38b4bbd574aa88679adef93"
export SWAPPER_CONTRACT="0x5d86bfd5a361bc652bc596dd2a77cd2bdba2bf35"
export LAYERZERO_ENDPOINT="0x1a44076050125825900e736c501f859c50fE728c" # Arbitrum Endpoint V2

# STARGATE DETAILS: Receiving from Base & Polygon
export STARGATE_SRC_EID=30184 # Base
export TRUSTED_STARGATE_POOL="0x27a16dc786820B16E5c9028b75B99F6f604b5d26" # Base USDC Pool
export RECEIVED_TOKEN="0xaf88d065e77c8cC2239327C5EDb3A432268e5831" # Arbitrum USDC
export OLD_RECEIVER="0xFE5fA0d938Eeb2aaEF18B8B8D910763234961ABd" # The current live receiver on Arbitrum

echo "========================================================"
echo "Deploying and Wire Rescuable StargateReceiverAdapter (ARBITRUM)"
echo "========================================================"

forge script script/DeployStargateRescuableReceiver.s.sol:DeployStargateRescuableReceiver \
    --rpc-url $RPC_URL \
    --broadcast \
    --verify \
    --etherscan-api-key $ARBISCAN_API_KEY \
    -vvvv

echo "========================================================"
echo "Deployment & Verification Complete!"
echo "========================================================"
