# OKX DEX Integration - Deployment Scripts

## 📋 Deployment Guide

This guide covers deployment of OKX DEX Adapter and TokenSwapperV2 to Base and Polygon chains.

---

## 🚀 Quick Start

### **Prerequisites**

1. Install Foundry (if not already installed):
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

2. Configure environment:
```bash
cp .env.example .env
# Edit .env with your private keys and RPC URLs
```

3. Compile contracts:
```bash
forge build
```

---

## 📝 Deployment Steps

### **Step 1: Deploy to Base Chain**

#### **1a. Deploy OKXDexAdapter**

```bash
forge script script/DeployOKXAdapterBase.s.sol:DeployOKXAdapterBase \
  --rpc-url base \
  --broadcast \
  --verify \
  --etherscan-api-key $BASESCAN_API_KEY \
  -vvv
```

**Environment Variables:**
```bash
export TOKEN_SWAPPER_ADDRESS=0xYourTokenSwapperAddress
```

**Expected Output:**
```
🚀 Deploying OKXDexAdapter to Base...
OKX Router: 0x4409921Ae43a39a11D90F7B7F96cfd0B8093d9fC
TokenSwapper: 0xYourTokenSwapperAddress
✅ OKXDexAdapter deployed to: 0xNewAdapterAddress
```

**Configuration:**
- OKX Router (Base): `0x4409921Ae43a39a11D90F7B7F96cfd0B8093d9fC`
- TokenSwapper: Your existing TokenSwapper address

---

### **Step 2: Deploy to Polygon Chain**

#### **2a. Deploy OKXDexAdapter**

```bash
forge script script/DeployOKXAdapterPolygon.s.sol:DeployOKXAdapterPolygon \
  --rpc-url polygon \
  --broadcast \
  --verify \
  --etherscan-api-key $POLYGONSCAN_API_KEY \
  -vvv
```

**Environment Variables:**
```bash
export TOKEN_SWAPPER_ADDRESS_POLYGON=0xYourTokenSwapperAddressOnPolygon
```

---

### **Step 3: Deploy to BSC (Binance Smart Chain)**

#### **3a. Deploy OKXDexAdapter**

```bash
forge script script/DeployOKXAdapterBSC.s.sol:DeployOKXAdapterBSC \
  --rpc-url bsc \
  --broadcast \
  --verify \
  --etherscan-api-key $BSCSCAN_API_KEY \
  -vvv
```

**Environment Variables:**
```bash
export TOKEN_SWAPPER_ADDRESS_BSC=0xYourTokenSwapperAddressOnBSC
```

**Configuration:**
- OKX Router (BSC): `0x4409921Ae43a39a11D90F7B7F96cfd0B8093d9fC` (verify!)

---

### **Step 4: Deploy to Arbitrum**

#### **4a. Deploy OKXDexAdapter**

```bash
forge script script/DeployOKXAdapterArbitrum.s.sol:DeployOKXAdapterArbitrum \
  --rpc-url arbitrum \
  --broadcast \
  --verify \
  --etherscan-api-key $ARBISCAN_API_KEY \
  -vvv
```

**Environment Variables:**
```bash
export TOKEN_SWAPPER_ADDRESS_ARBITRUM=0xYourTokenSwapperAddressOnArbitrum
```

**Configuration:**
- OKX Router (Arbitrum): `0x4409921Ae43a39a11D90F7B7F96cfd0B8093d9fC` (verify!)

---

## 🔧 Manual Configuration

If you need to manually configure TokenSwapperV2:

### **Set OKX Adapter**

```solidity
// Call on TokenSwapperV2 contract
function setOKXDexAdapter(address _newAdapter) external onlyOwner
```

**Parameters:**
- `_newAdapter`: OKXDexAdapter address from deployment

### **Enable OKX Integration**

```solidity
// Call on TokenSwapperV2 contract
function setOKXIntegrationEnabled(bool _enabled) external onlyOwner
```

**Parameters:**
- `_enabled`: `true` to enable

### **Set Max Price Impact**

```solidity
// Call on TokenSwapperV2 contract
function setMaxPriceImpactBps(uint256 _maxImpactBps) external onlyOwner
```

**Parameters:**
- `_maxImpactBps`: `500` for 5% (recommended)

---

## ✅ Verification

### **Check Deployment**

```bash
npx hardhat run scripts/verify-deployment.js --network base
```

**Expected Output:**
```
Verifying OKX DEX Integration on Base...
✅ OKXDexAdapter: 0xAdapterAddress
✅ TokenSwapperV2: 0xTokenSwapperV2Address
✅ OKX Integration: Enabled
✅ Max Price Impact: 500 bps
✅ OKX Router: 0xOKXRouterAddress
All checks passed!
```

### **Test Swap**

```bash
npx hardhat run scripts/test-swap.js --network base
```

**Test Parameters:**
- Token In: 10 IDRT
- Token Out: USDC
- Expected: Better rate than Uniswap-only

---

## 📊 Contract Addresses

### **Base Chain**

| Contract | Address | Deployed |
|----------|---------|----------|
| OKX Router | `0x4409921Ae43a39a11D90F7B7F96cfd0B8093d9fC` | ✅ Existing |
| OKXDexAdapter | _Deployed_ | ⏳ Use `deploy-okx-adapter.js` |
| TokenSwapperV2 | _Deployed_ | ⏳ Pending |
| USDC | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` | ✅ Existing |
| IDRX | `0x18Bc5bcC660cf2B9cE3cd51a404aFe1a0cBD3C22` | ✅ Existing |

### **Polygon Chain**

| Contract | Address | Deployed |
|----------|---------|----------|
| OKX Router | _Verify on OKX DEX docs_ | ⏳ Pending |
| OKXDexAdapter | _Deployed_ | ⏳ Use `deploy-okx-adapter.js --network polygon` |
| TokenSwapperV2 | _Deployed_ | ⏳ Pending |
| USDC | `0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359` | ✅ Existing |
| IDRT | `0x554cd6bdD03214b10AafA3e0D4D42De0C5D2937b` | ✅ Existing |

### **BSC (Binance Smart Chain)**

| Contract | Address | Deployed |
|----------|---------|----------|
| OKX Router | `0x4409921Ae43a39a11D90F7B7F96cfd0B8093d9fC` (verify!) | ⏳ Pending |
| OKXDexAdapter | _Deployed_ | ⏳ Use `deploy-okx-adapter-bsc.js` |
| TokenSwapperV2 | _Deployed_ | ⏳ Pending |
| USDC | `0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d` | ✅ Existing |
| USDT | `0x55d398326f99059fF775485246999027B31979F5` | ✅ Existing |

### **Arbitrum**

| Contract | Address | Deployed |
|----------|---------|----------|
| OKX Router | `0x4409921Ae43a39a11D90F7B7F96cfd0B8093d9fC` (verify!) | ⏳ Pending |
| OKXDexAdapter | _Deployed_ | ⏳ Use `deploy-okx-adapter-arbitrum.js` |
| TokenSwapperV2 | _Deployed_ | ⏳ Pending |
| USDC | `0xaf88d065e77c8cC2239327C5EDb3A432268e5831` | ✅ Existing |
| USDT | `0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9` | ✅ Existing |

---

## 🔍 Monitoring

### **Track Price Impact**

Monitor `PriceImpactWarning` events:
```javascript
contract.on("PriceImpactWarning", (tokenIn, tokenOut, amountIn, impactBps, isAcceptable) => {
    console.log(`Price Impact: ${impactBps} bps - Acceptable: ${isAcceptable}`);
});
```

### **Track Liquidity Source**

Monitor `LiquiditySourceSelected` events:
```javascript
contract.on("LiquiditySourceSelected", (tokenIn, tokenOut, amountIn, source, amountOut) => {
    const sources = ["OKX_DEX", "UNISWAP_V4", "UNISWAP_V3", "UNISWAP_V2", "SIMULATION"];
    console.log(`Source: ${sources[source]} - Amount Out: ${amountOut}`);
});
```

---

## ⚠️ Troubleshooting

### **Issue: Deployment fails with "insufficient funds"**

**Solution:**
- Ensure deployer account has enough native tokens (ETH/MATIC)
- Check gas price settings in hardhat config

### **Issue: OKX quote returns 0**

**Solution:**
- Verify OKX Router address is correct
- Check if token pair is supported by OKX
- Try smaller amount for testing

### **Issue: Price impact too high**

**Solution:**
- Increase `okxMaxPriceImpactBps` (not recommended >1000 bps)
- Reduce swap amount
- Check if liquidity is available on OKX

---

## 📞 Support

For issues or questions:
- Check deployment logs
- Review contract events
- Contact development team

---

**Last Updated:** 2026-03-29  
**Version:** 1.0
