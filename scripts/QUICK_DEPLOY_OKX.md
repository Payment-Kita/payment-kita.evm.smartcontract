# Quick OKX Adapter Deployment Guide

## 🚀 Quick Deploy (One-Liner per Chain)

### **Base**
```bash
cd payment-kita.evm.smartcontract
export PRIVATE_KEY=your_private_key
export BASESCAN_API_KEY=your_basescan_key

forge script script/DeployOKXAdapterBase.s.sol:DeployOKXAdapterBase \
  --rpc-url base \
  --broadcast \
  --verify \
  -vvv
```

### **Polygon**
```bash
export POLYGONSCAN_API_KEY=your_polygonscan_key

forge script script/DeployOKXAdapterPolygon.s.sol:DeployOKXAdapterPolygon \
  --rpc-url polygon \
  --broadcast \
  --verify \
  -vvv
```

### **Arbitrum**
```bash
export ARBISCAN_API_KEY=your_arbiscan_key

forge script script/DeployOKXAdapterArbitrum.s.sol:DeployOKXAdapterArbitrum \
  --rpc-url arbitrum \
  --broadcast \
  --verify \
  -vvv
```

---

## ⚠️ Environment Variables Required

Create `.env` file:
```bash
# Your deployer private key
PRIVATE_KEY=0x...

# Etherscan API keys for verification
BASESCAN_API_KEY=...
POLYGONSCAN_API_KEY=...
ARBISCAN_API_KEY=...

# Existing TokenSwapper address (for wiring)
TOKEN_SWAPPER_ADDRESS=0x8B6c7770D4B8AaD2d600e0cf5df3Eea5Bc0EB0fe  # Base
TOKEN_SWAPPER_ADDRESS_POLYGON=0xe50BDD9CA4289CfD675240B3A7294035655AF8d2  # Polygon
TOKEN_SWAPPER_ADDRESS_ARBITRUM=0xD12200745Fbb85f37F439DC81F5a649FF131C675  # Arbitrum
```

---

## 📝 Post-Deployment

After successful deployment, update CHAIN_*.md:

```markdown
## OKX DEX Integration
OKXDexAdapter (Base): `0xYourDeployedAddress`
OKXDexAdapter (Polygon): `0xYourDeployedAddress`
OKXDexAdapter (Arbitrum): `0xYourDeployedAddress`
```

---

## ✅ Verification

Check deployment:
```bash
# Check adapter deployed
cast call $OKX_ADAPTER_ADDRESS "okxRouter()(address)"

# Check TokenSwapper configured
cast call $OKX_ADAPTER_ADDRESS "tokenSwapper()(address)"
```

---

**Document Version:** 1.0  
**Status:** ✅ READY FOR DEPLOYMENT
