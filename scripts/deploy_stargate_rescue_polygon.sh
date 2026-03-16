#!/bin/bash
set -a
source .env
set +a

# Defaults for Polygon
export RPC_URL=${POLYGON_RPC_URL}
export GATEWAY_CONTRACT="0xcb5fC6c5E7895406b797B11F91AF67A07027a26F"
export VAULT_CONTRACT="0x28ee150c1F23952cFe01B38612c4D45E28FDA4A3"
export SWAPPER_CONTRACT="0xe50BDD9CA4289CfD675240B3A7294035655AF8d2"
export LAYERZERO_ENDPOINT="0x1a44076050125825900e736c501f859c50fE728c" # Polygon Endpoint V2

# STARGATE DETAILS: Receiving from Base & Arbitrum (we set one default trusted pool during init)
# We use Arbitrum Pool here or any default. Can be updated later via setRoute.
export STARGATE_SRC_EID=30110 # Arbitrum (example default route to set)
export TRUSTED_STARGATE_POOL="0xe8CDF27AcD73a434D661C84887215F7598e7d0d3" # Arbitrum USDC Pool
export RECEIVED_TOKEN="0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359" # Polygon USDC
export OLD_RECEIVER="0x5098Df68C5935c923CD551649c74725989bDc3DC" # The current stuck receiver on Polygon

echo "========================================================"
echo "Deploying and Wire Rescuable StargateReceiverAdapter (POLYGON)"
echo "========================================================"

forge script script/DeployStargateRescuableReceiver.s.sol:DeployStargateRescuableReceiver \
    --rpc-url $RPC_URL \
    --broadcast \
    --verify \
    --etherscan-api-key $POLYGONSCAN_API_KEY \
    -vvvv

echo "========================================================"
echo "Deployment & Verification Complete!"
echo "========================================================"
