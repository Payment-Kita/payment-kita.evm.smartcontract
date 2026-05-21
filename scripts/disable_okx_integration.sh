#!/bin/bash

# ============================================================================
# Disable OKX Integration - All Chains
# ============================================================================
# This script disables OKX integration on all chains
# Use this when FE/BE are not ready yet
# ============================================================================

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  Disable OKX Integration - All Chains${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

# Check PRIVATE_KEY
if [ -z "$PRIVATE_KEY" ]; then
    echo -e "${RED}Error: PRIVATE_KEY not set${NC}"
    echo "Please run: source .env"
    exit 1
fi

# OKX Adapter Addresses (from deployment)
OKX_ADAPTER_BASE="0xf0126D8C70AC926797De60A5921F2b0b3d70dbc0"
OKX_ADAPTER_POLYGON="0x08409b0fa63b0bCEb4c4B49DBf286ff943b60011"
OKX_ADAPTER_ARBITRUM="0xa60A1DB6b4E6F8836Cc9Ee2cad15b55B473d24F3"

# RPC URLs
BASE_RPC="https://base-mainnet.g.alchemy.com/v2/K9PzwLloeXxcOuFEx_fgR"
POLYGON_RPC="https://polygon-mainnet.g.alchemy.com/v2/K9PzwLloeXxcOuFEx_fgR"
ARBITRUM_RPC="https://arb1.arbitrum.io/rpc"

echo "Deployed OKX Adapters:"
echo "  Base:      $OKX_ADAPTER_BASE"
echo "  Polygon:   $OKX_ADAPTER_POLYGON"
echo "  Arbitrum:  $OKX_ADAPTER_ARBITRUM"
echo ""
echo "This will DISABLE OKX integration on all chains."
echo "The system will continue using the original TokenSwapper."
echo ""
read -p "Continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo -e "${YELLOW}Cancelled${NC}"
    exit 0
fi

echo ""
echo -e "${YELLOW}Starting reset process...${NC}"
echo ""

# Disable on Base
echo -e "${YELLOW}[1/3] Disabling on Base...${NC}"
cast send $OKX_ADAPTER_BASE "setOKXIntegrationEnabled(bool)" false \
    --private-key $PRIVATE_KEY \
    --rpc-url $BASE_RPC \
    -q

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Base: OKX integration disabled${NC}"
else
    echo -e "${RED}✗ Base: Failed${NC}"
fi
echo ""

# Disable on Polygon
echo -e "${YELLOW}[2/3] Disabling on Polygon...${NC}"
cast send $OKX_ADAPTER_POLYGON "setOKXIntegrationEnabled(bool)" false \
    --private-key $PRIVATE_KEY \
    --rpc-url $POLYGON_RPC \
    -q

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Polygon: OKX integration disabled${NC}"
else
    echo -e "${RED}✗ Polygon: Failed${NC}"
fi
echo ""

# Disable on Arbitrum
echo -e "${YELLOW}[3/3] Disabling on Arbitrum...${NC}"
cast send $OKX_ADAPTER_ARBITRUM "setOKXIntegrationEnabled(bool)" false \
    --private-key $PRIVATE_KEY \
    --rpc-url $ARBITRUM_RPC \
    -q

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Arbitrum: OKX integration disabled${NC}"
else
    echo -e "${RED}✗ Arbitrum: Failed${NC}"
fi
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Reset Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "OKX integration has been DISABLED on all chains."
echo "System is now using the original TokenSwapper."
echo ""
echo "To RE-ENABLE OKX integration later:"
echo "  cast send <OKX_ADAPTER> \"setOKXIntegrationEnabled(bool)\" true ..."
echo ""
echo "Verification:"
echo "  cast call <OKX_ADAPTER> \"integrationEnabled()(bool)\""
echo "  Expected: false"
echo ""
