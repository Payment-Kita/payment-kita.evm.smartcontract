#!/bin/bash

# ============================================================================
# Quick Reset Script - Disable OKX Integration
# ============================================================================
# Use this script to quickly disable OKX integration if issues occur
# This will revert to using the original TokenSwapper
# ============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=================================================${NC}"
echo -e "${YELLOW}   Quick Reset - Disable OKX Integration        ${NC}"
echo -e "${YELLOW}=================================================${NC}"
echo ""

# Check if PRIVATE_KEY is set
if [ -z "$PRIVATE_KEY" ]; then
    echo -e "${RED}Error: PRIVATE_KEY environment variable not set${NC}"
    echo "Please set PRIVATE_KEY and try again"
    exit 1
fi

# Function to disable OKX integration on a chain
disable_okx_integration() {
    local chain_name=$1
    local rpc_url=$2
    local okx_adapter_address=$3
    
    echo -e "${YELLOW}Disabling OKX integration on $chain_name...${NC}"
    echo "OKX Adapter: $okx_adapter_address"
    echo "RPC: $rpc_url"
    echo ""
    
    # Disable OKX integration
    cast send $okx_adapter_address "setOKXIntegrationEnabled(bool)" false \
        --private-key $PRIVATE_KEY \
        --rpc-url $rpc_url \
        -vvv
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ OKX integration disabled on $chain_name${NC}"
    else
        echo -e "${RED}✗ Failed to disable OKX integration on $chain_name${NC}"
        return 1
    fi
    
    echo ""
}

# Function to verify OKX integration is disabled
verify_disabled() {
    local chain_name=$1
    local rpc_url=$2
    local okx_adapter_address=$3
    
    echo -e "${YELLOW}Verifying OKX integration on $chain_name...${NC}"
    
    local integration_enabled=$(cast call $okx_adapter_address "integrationEnabled()(bool)" --rpc-url $rpc_url)
    
    if [ "$integration_enabled" == "false" ]; then
        echo -e "${GREEN}✓ OKX integration is disabled on $chain_name${NC}"
        return 0
    else
        echo -e "${RED}✗ OKX integration is still enabled on $chain_name${NC}"
        return 1
    fi
}

# Main script
echo "This script will disable OKX integration on all chains."
echo "The system will revert to using the original TokenSwapper."
echo ""
read -p "Do you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo -e "${YELLOW}Operation cancelled${NC}"
    exit 0
fi

echo ""
echo -e "${YELLOW}Starting reset process...${NC}"
echo ""

# Base
disable_okx_integration "Base" "https://base-mainnet.g.alchemy.com/v2/K9PzwLloeXxcOuFEx_fgR" "$OKX_ADAPTER_BASE"
verify_disabled "Base" "https://base-mainnet.g.alchemy.com/v2/K9PzwLloeXxcOuFEx_fgR" "$OKX_ADAPTER_BASE"

# Polygon
disable_okx_integration "Polygon" "https://polygon-mainnet.g.alchemy.com/v2/K9PzwLloeXxcOuFEx_fgR" "$OKX_ADAPTER_POLYGON"
verify_disabled "Polygon" "https://polygon-mainnet.g.alchemy.com/v2/K9PzwLloeXxcOuFEx_fgR" "$OKX_ADAPTER_POLYGON"

# Arbitrum
disable_okx_integration "Arbitrum" "https://arb1.arbitrum.io/rpc" "$OKX_ADAPTER_ARBITRUM"
verify_disabled "Arbitrum" "https://arb1.arbitrum.io/rpc" "$OKX_ADAPTER_ARBITRUM"

echo ""
echo -e "${GREEN}=================================================${NC}"
echo -e "${GREEN}   Reset Complete!                               ${NC}"
echo -e "${GREEN}=================================================${NC}"
echo ""
echo "OKX integration has been disabled on all chains."
echo "The system is now using the original TokenSwapper."
echo ""
echo "Next steps:"
echo "1. Verify swaps are working correctly"
echo "2. Investigate the issue with OKX Adapter"
echo "3. Re-enable OKX integration when ready"
echo ""
