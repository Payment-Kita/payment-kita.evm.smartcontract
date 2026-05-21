#!/bin/bash

# Contract Verification Script
# Usage: ./verify_contracts.sh

export BASESCAN_API_KEY=4H13JI3QBQP2FYEP73864NRYXAC8FIW9ZR
export POLYGONSCAN_API_KEY=4H13JI3QBQP2FYEP73864NRYXAC8FIW9ZR
export ARBISCAN_API_KEY=4H13JI3QBQP2FYEP73864NRYXAC8FIW9ZR

echo "=========================================="
echo "   Contract Verification Script"
echo "=========================================="
echo ""

# Base
echo "=== VERIFYING BASE ==="
echo "Contract: 0xf0126D8C70AC926797De60A5921F2b0b3d70dbc0"
echo "OKX Router: 0x4409921Ae43a39a11D90F7B7F96cfd0B8093d9fC"
echo "TokenSwapper: 0x8B6c7770D4B8AaD2d600e0cf5df3Eea5Bc0EB0fe"
echo ""

forge verify-contract \
  --chain-id 8453 \
  --compiler-version v0.8.20 \
  --optimizer-runs 200 \
  --constructor-args 0x0000000000000000000000004409921ae43a39a11d90f7b7f96cfd0b8093d9fc0000000000000000000000008b6c7770d4b8aad2d600e0cf5df3eea5b6c0eb0fe \
  0xf0126D8C70AC926797De60A5921F2b0b3d70dbc0 \
  src/integrations/okx/OKXDexAdapter.sol:OKXDexAdapter \
  --etherscan-api-key $BASESCAN_API_KEY \
  -vvv

echo ""
echo "Base verification complete!"
echo ""

# Polygon
echo "=== VERIFYING POLYGON ==="
echo "Contract: 0x08409b0fa63b0bCEb4c4B49DBf286ff943b60011"
echo "OKX Router: 0x057cFd839AA88994d1A8A8C6D336CF21550F05Ef"
echo "TokenSwapper: 0xe50BDD9CA4289CfD675240B3A7294035655AF8d2"
echo ""

forge verify-contract \
  --chain-id 137 \
  --compiler-version v0.8.20 \
  --optimizer-runs 200 \
  --constructor-args 0x000000000000000000000000057cfd839aa88994d1a8a8c6d336cf21550f05ef000000000000000000000000e50bdd9ca4289cfd675240b3a7294035655af8d2 \
  0x08409b0fa63b0bCEb4c4B49DBf286ff943b60011 \
  src/integrations/okx/OKXDexAdapter.sol:OKXDexAdapter \
  --etherscan-api-key $POLYGONSCAN_API_KEY \
  -vvv

echo ""
echo "Polygon verification complete!"
echo ""

# Arbitrum
echo "=== VERIFYING ARBITRUM ==="
echo "Contract: 0xa60A1DB6b4E6F8836Cc9Ee2cad15b55B473d24F3"
echo "OKX Router: 0x368E01160C2244B0363a35B3fF0A971E44a89284"
echo "TokenSwapper: 0xD12200745Fbb85f37F439DC81F5a649FF131C675"
echo ""

forge verify-contract \
  --chain-id 42161 \
  --compiler-version v0.8.20 \
  --optimizer-runs 200 \
  --constructor-args 0x000000000000000000000000368e01160c2244b0363a35b3ff0a971e44a89284000000000000000000000000d12200745fbb85f37f439dc81f5a649ff131c675 \
  0xa60A1DB6b4E6F8836Cc9Ee2cad15b55B473d24F3 \
  src/integrations/okx/OKXDexAdapter.sol:OKXDexAdapter \
  --etherscan-api-key $ARBISCAN_API_KEY \
  -vvv

echo ""
echo "Arbitrum verification complete!"
echo ""
echo "=========================================="
echo "   All Verifications Complete!"
echo "=========================================="
