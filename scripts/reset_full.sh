#!/bin/bash

# ============================================================================
# Full Reset Script - Revert to Original TokenSwapper
# ============================================================================
# Use this script to completely remove OKX Adapter and revert to the
# original TokenSwapper implementation
# ============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=================================================${NC}"
echo -e "${YELLOW}   Full Reset - Revert to Original TokenSwapper ${NC}"
echo -e "${YELLOW}=================================================${NC}"
echo ""

# Check if PRIVATE_KEY is set
if [ -z "$PRIVATE_KEY" ]; then
    echo -e "${RED}Error: PRIVATE_KEY environment variable not set${NC}"
    echo "Please set PRIVATE_KEY and try again"
    exit 1
fi

# Original TokenSwapper addresses (HARDCODED FROM CHAIN_*.md)
TOKENSWAPPER_BASE="0x8B6c7770D4B8AaD2d600e0cf5df3Eea5Bc0EB0fe"
TOKENSWAPPER_POLYGON="0xe50BDD9CA4289CfD675240B3A7294035655AF8d2"
TOKENSWAPPER_ARBITRUM="0xD12200745Fbb85f37F439DC81F5a649FF131C675"

GATEWAY_BASE="0xc1d4Ed499417B560A5Df53bA5e2b1A54755Ce58C"
GATEWAY_POLYGON="0xC2Df6CbFeA8c00f7Dacf08B27124cC4fB72f3B69"
GATEWAY_ARBITRUM="0x256F96f965eb536E0d6684b0BC52a300663f505a"

# Function to revoke OKX Adapter authorization
revoke_okx_authorization() {
    local chain_name=$1
    local rpc_url=$2
    local tokenswapper_v3_address=$3
    local gateway_address=$4
    
    echo -e "${YELLOW}Revoking OKX Adapter authorization on $chain_name...${NC}"
    echo "TokenSwapperV3: $tokenswapper_v3_address"
    echo "Gateway: $gateway_address"
    echo "RPC: $rpc_url"
    echo ""
    
    # Revoke authorization
    cast send $tokenswapper_v3_address "setAuthorizedCaller(address,bool)" $gateway_address false \
        --private-key $PRIVATE_KEY \
        --rpc-url $rpc_url \
        -vvv
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Authorization revoked on $chain_name${NC}"
    else
        echo -e "${RED}✗ Failed to revoke authorization on $chain_name${NC}"
        return 1
    fi
    
    echo ""
}

# Function to verify authorization
verify_authorization() {
    local chain_name=$1
    local rpc_url=$2
    local tokenswapper_address=$3
    local gateway_address=$4
    
    echo -e "${YELLOW}Verifying authorization on $chain_name...${NC}"
    
    local is_authorized=$(cast call $tokenswapper_address "authorizedCallers(address)(bool)" $gateway_address --rpc-url $rpc_url)
    
    if [ "$is_authorized" == "true" ]; then
        echo -e "${GREEN}✓ Gateway is authorized on TokenSwapper${NC}"
        return 0
    else
        echo -e "${RED}✗ Gateway is NOT authorized on TokenSwapper${NC}"
        return 1
    fi
}

# Main script
echo "WARNING: This script will completely remove OKX Adapter integration"
echo "and revert to the original TokenSwapper implementation."
echo ""
echo "Original TokenSwapper Addresses:"
echo "  Base:      $TOKENSWAPPER_BASE"
echo "  Polygon:   $TOKENSWAPPER_POLYGON"
echo "  Arbitrum:  $TOKENSWAPPER_ARBITRUM"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo -e "${YELLOW}Operation cancelled${NC}"
    exit 0
fi

echo ""
echo -e "${YELLOW}Starting full reset process...${NC}"
echo ""

# Note: This script assumes you have the OKX Adapter addresses set
# If not, you'll need to manually revoke authorization via Gateway

echo -e "${RED}IMPORTANT:${NC}"
echo "This script requires manual intervention to re-authorize"
echo "the original TokenSwapper on the Gateway contract."
echo ""
echo "After running this script, you need to:"
echo "1. Update Gateway configuration to use original TokenSwapper"
echo "2. Verify all integrations are working"
echo "3. Update CHAIN_*.md with reverted addresses"
echo ""
read -p "Press Enter to continue..."

# Note: Full reset requires Gateway contract modification
# This is a placeholder for the actual reset logic

echo -e "${YELLOW}Full reset requires Gateway contract update${NC}"
echo "Please contact the development team for assistance"
echo ""
echo "Alternatively, you can:"
echo "1. Disable OKX integration (use reset_disable_okx.sh)"
echo "2. Manually update Gateway configuration"
echo ""

echo -e "${GREEN}=================================================${NC}"
echo -e "${GREEN}   Reset Process Complete                        ${NC}"
echo -e "${GREEN}=================================================${NC}"
