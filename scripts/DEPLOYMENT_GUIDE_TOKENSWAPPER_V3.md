# TokenSwapperV3 Deployment Guide

## 📋 Overview

This guide covers the complete deployment and configuration of TokenSwapperV3 with proper wiring to existing systems.

**Components:**
- TokenSwapperV3 (Advanced swapper with split-swap, oracles, caching)
- OKX DEX Adapter (OKX integration)
- Chainlink Oracles (Price validation)
- Existing system integration (Gateway, Registry, TokenSwapper)

---

## 🚀 Prerequisites

### **Environment Setup:**

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Set environment variables
export PRIVATE_KEY=your_deployer_private_key
export BASESCAN_API_KEY=your_basescan_key
export POLYGONSCAN_API_KEY=your_polygonscan_key
export ARBISCAN_API_KEY=your_arbiscan_key
```

### **Required Environment Variables:**

Create `.env` file with:

```bash
# Network Configuration
BASE_RPC_URL=https://base-mainnet.g.alchemy.com/v2/YOUR_KEY
POLYGON_RPC_URL=https://polygon-mainnet.g.alchemy.com/v2/YOUR_KEY
ARBITRUM_RPC_URL=https://arb1.arbitrum.io/rpc

# Token Addresses (Base example)
BASE_BRIDGE_TOKEN=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913  # USDC
BASE_NATIVE_TOKEN=0x4200000000000000000000000000000000000006  # WETH
BASE_IDRX=0x18Bc5bcC660cf2B9cE3cd51a404aFe1a0cBD3C22
BASE_IDRT=0x554cd6bdD03214b10AafA3e0D4D42De0C5D2937b
BASE_USDT=0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2
BASE_WBTC=0x1234... # Configure as needed

# Token Decimals
BASE_BRIDGE_TOKEN_DECIMAL=6
BASE_NATIVE_TOKEN_DECIMAL=18
BASE_IDRX_DECIMAL=2
BASE_IDRT_DECIMAL=6

# Existing System Addresses
BASE_TOKEN_SWAPPER=0x...  # Existing TokenSwapper address
BASE_GATEWAY=0x...        # Existing Gateway address
BASE_TOKEN_REGISTRY=0x... # Existing Registry address

# OKX Adapter (deploy new or use existing)
BASE_OKX_ADAPTER=0x...    # Deploy new if not set

# Chainlink Oracles (Base)
BASE_USDC_ORACLE=0x7e860098f58bBFC8648a4311b374B1D669a2bc6B
BASE_ETH_ORACLE=0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70

# V3 Router
BASE_V3_ROUTER=0x...

# Liquidity Providers
LIQUIDITY_PROVIDER_1=0x...
LIQUIDITY_PROVIDER_2=0x...

# Bridge Configurations
BASE_CCIP_ROUTER=0x...
BASE_STARGATE_ROUTER=0x...
```

---

## 📝 Deployment Steps

### **Step 1: Deploy TokenSwapperV3**

```bash
cd payment-kita.evm.smartcontract

# For Base
forge script script/DeployTokenSwapperV3.s.sol:DeployTokenSwapperV3 \
  --rpc-url base \
  --broadcast \
  --verify \
  --etherscan-api-key $BASESCAN_API_KEY \
  -vvv

# For Polygon
forge script script/DeployTokenSwapperV3.s.sol:DeployTokenSwapperV3 \
  --rpc-url polygon \
  --broadcast \
  --verify \
  --etherscan-api-key $POLYGONSCAN_API_KEY \
  -vvv

# For Arbitrum
forge script script/DeployTokenSwapperV3.s.sol:DeployTokenSwapperV3 \
  --rpc-url arbitrum \
  --broadcast \
  --verify \
  --etherscan-api-key $ARBISCAN_API_KEY \
  -vvv
```

**Output:**
```
✅ TokenSwapperV3 deployed: 0xYourContractAddress
✅ OKX DEX Adapter deployed: 0xYourOKXAdapterAddress
✅ Configuration complete
✅ Tokens registered
✅ Oracles configured
✅ Features enabled
```

**Save the deployed addresses:**
```bash
export BASE_TOKEN_SWAPPER_V3=0xYourContractAddress
export BASE_OKX_ADAPTER=0xYourOKXAdapterAddress
```

---

### **Step 2: Wire to Existing System**

```bash
# Update .env with deployed addresses
# Then run wiring script

forge script script/WireTokenSwapperV3.s.sol:WireTokenSwapperV3 \
  --rpc-url base \
  --broadcast \
  -vvv
```

**This script will:**
1. Authorize Gateway to call TokenSwapperV3
2. Configure V3 pools for supported token pairs
3. Authorize liquidity providers
4. Configure bridge protocols
5. Sync with token registry
6. Run validation checks

---

### **Step 3: Verify Deployment**

```bash
# Verify contract on Basescan
forge verify-contract \
  --chain-id 8453 \
  --num-of-optimizations 200 \
  --compiler-version v0.8.20 \
  0xYourContractAddress \
  src/TokenSwapperV3.sol:TokenSwapperV3 \
  --etherscan-api-key $BASESCAN_API_KEY
```

---

## 🔧 Configuration Details

### **V3 Pool Configuration:**

The deployment script automatically configures these pools:

| Pair | Fee Tier | Priority |
|------|----------|----------|
| IDRX/USDC | 0.01% (100) | High |
| USDC/USDT | 0.01% (100) | High |
| USDC/WETH | 0.05% (500) | Medium |
| USDC/WBTC | 0.05% (500) | Medium |
| IDRT/USDC | 0.01% (100) | High (Polygon) |

### **Oracle Configuration:**

| Token | Oracle | Max Staleness | Min Price | Max Price |
|-------|--------|---------------|-----------|-----------|
| USDC | Chainlink USDC/USD | 1 hour | $0.50 | $1.50 |
| WETH | Chainlink ETH/USD | 1 hour | $1,000 | $10,000 |

### **Feature Flags:**

| Feature | Default | Can Disable |
|---------|---------|-------------|
| OKX Integration | ✅ Enabled | Yes |
| Split-Swap | ✅ Enabled | Yes |
| Oracle Validation | ✅ Enabled | Yes |
| Quote Caching | ✅ Enabled | Yes |

---

## ⚙️ Post-Deployment Configuration

### **Add New Token:**

```bash
# Set environment variables
export BASE_NEW_TOKEN=0x...
export BASE_NEW_TOKEN_DECIMAL=18

# Run token registration
forge script script/ConfigureTokenSwapperV3.s.sol:ConfigureTokenSwapperV3 \
  --rpc-url base \
  --broadcast \
  -vvv
```

### **Update Oracle:**

```solidity
// Call on TokenSwapperV3
swapperV3.setTokenOracle(
    tokenAddress,
    newOracleAddress,
    3600, // 1 hour staleness
    minPrice,
    maxPrice
);
```

### **Configure Bridge:**

```solidity
// Set bridge configuration
swapperV3.setBridgeConfig(
    chainId,
    bridgeType, // 0=CCIP, 1=Stargate, 2=Hyperbridge
    BridgeConfig({
        bridgeAddress: bridgeAddress,
        isActive: true,
        minAmount: 1000 * 10**6, // 1000 USDC
        maxAmount: 1000000 * 10**6, // 1M USDC
        feeBps: 10 // 0.1%
    })
);
```

---

## 🧪 Testing

### **Test Swap:**

```bash
# Small test swap
cast send \
  $BASE_TOKEN_SWAPPER_V3 \
  "executeSplitSwap(address,address,uint256,uint256,address)" \
  $USDC_ADDRESS \
  $IDRX_ADDRESS \
  1000000000  # 1000 USDC (6 decimals) \
  0          # No min amount for testing \
  $YOUR_ADDRESS \
  --private-key $PRIVATE_KEY \
  --rpc-url $BASE_RPC_URL
```

### **Monitor Events:**

```bash
# Watch for swap events
cast watch \
  $BASE_TOKEN_SWAPPER_V3 \
  "SplitSwapExecuted(uint64,uint64,address,address,uint256,uint256,uint8,uint256)" \
  --rpc-url $BASE_RPC_URL
```

---

## ⚠️ Troubleshooting

### **Issue: Deployment fails with "out of gas"**

**Solution:**
```bash
# Increase gas limit
forge script ... --gas-limit 10000000
```

### **Issue: Token not supported**

**Solution:**
```bash
# Register token in registry first
# Then re-run wiring script
forge script script/WireTokenSwapperV3.s.sol:WireTokenSwapperV3 ...
```

### **Issue: Oracle returns stale price**

**Solution:**
```solidity
// Increase max staleness
swapperV3.setTokenOracle(
    token,
    oracle,
    7200, // 2 hours instead of 1
    minPrice,
    maxPrice
);
```

### **Issue: Split-swap not executing**

**Solution:**
```bash
# Check if enabled
cast call $BASE_TOKEN_SWAPPER_V3 "splitSwapEnabled()(bool)"

# Enable if disabled
cast send $BASE_TOKEN_SWAPPER_V3 "setSplitSwapEnabled(bool)" true \
  --private-key $PRIVATE_KEY
```

---

## 📊 Expected Results

### **Deployment Output:**

```
╔════════════════════════════════════════════════════════╗
║           Deployment Summary                           ║
╚════════════════════════════════════════════════════════╝

Network: BASE

Contracts Deployed:
  TokenSwapperV3: 0x...
  OKX DEX Adapter: 0x...

Configuration:
  Bridge Token: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
  Configured Tokens: 8
  Max Price Impact: 500 bps
  Max Oracle Deviation: 500 bps
  Quote Cache Validity: 30 s

Features:
  OKX Integration: ✓ Enabled
  Split-Swap: ✓ Enabled
  Oracle Validation: ✓ Enabled

╔════════════════════════════════════════════════════════╗
║              ✅ Deployment Complete!                   ║
╚════════════════════════════════════════════════════════╝
```

---

## 📞 Support

For issues or questions:
- Check deployment logs
- Review contract events
- Contact development team

---

**Document Version:** 1.0  
**Last Updated:** 2026-03-29  
**Status:** ✅ READY FOR DEPLOYMENT
