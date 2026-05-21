# TokenSwapperV3 Deployment - Final Instructions

## ⚠️ IMPORTANT: OKX Router Address Verification

**OKX DEX Router addresses BELUM terverifikasi!** 

Sebelum deployment production, **VERIFIKASI** OKX Router address yang benar dari:
- OKX Documentation: https://web3.okx.com/id/onchainos/dev-docs/trade/dex-smart-contract
- OKX Support / Developer Relations
- OKX DEX UI (inspect network calls)

**Current Status:** Deployment scripts menggunakan `address(0)` sebagai placeholder untuk OKX Router.

**Post-Deployment Configuration:**
```solidity
// Setelah deploy, configure OKX Router via:
cast send $OKX_ADAPTER_ADDRESS "setOKXRouter(address)" $OKX_ROUTER_ADDRESS \
  --private-key $PRIVATE_KEY \
  --rpc-url $RPC_URL
```

---

## 🚀 Deployment Steps

### **1. DRY RUN (Recommended)**

```bash
cd payment-kita.evm.smartcontract
source .env

# Base
forge script script/DeployBase.s.sol:DeployBase \
  --rpc-url base \
  -vvv

# Polygon
forge script script/DeployPolygon.s.sol:DeployPolygon \
  --rpc-url polygon \
  -vvv

# Arbitrum
forge script script/DeployArbitrum.s.sol:DeployArbitrum \
  --rpc-url arbitrum \
  -vvv
```

### **2. BROADCAST + VERIFY**

```bash
# Base
forge script script/DeployBase.s.sol:DeployBase \
  --rpc-url base \
  --broadcast \
  --verify \
  --etherscan-api-key $BASESCAN_API_KEY \
  -vvv

# Polygon
forge script script/DeployPolygon.s.sol:DeployPolygon \
  --rpc-url polygon \
  --broadcast \
  --verify \
  --etherscan-api-key $POLYGONSCAN_API_KEY \
  -vvv

# Arbitrum
forge script script/DeployArbitrum.s.sol:DeployArbitrum \
  --rpc-url arbitrum \
  --broadcast \
  --verify \
  --etherscan-api-key $ARBISCAN_API_KEY \
  -vvv
```

---

## 📝 Post-Deployment Configuration

### **1. Update CHAIN_*.md**

Setelah deployment berhasil, **UPDATE** file CHAIN_*.md dengan deployed addresses:

**CHAIN_BASE.md:**
```markdown
## TokenSwapperV3 + OKX Integration
TokenSwapperV3: `0xYourDeployedAddress`
OKXDexAdapter: `0xYourDeployedAddress`
```

**CHAIN_POLYGON.md:**
```markdown
## TokenSwapperV3 + OKX Integration
TokenSwapperV3: `0xYourDeployedAddress`
OKXDexAdapter: `0xYourDeployedAddress`
```

**CHAIN_ARBITRUM.md:**
```markdown
## TokenSwapperV3 + OKX Integration
TokenSwapperV3: `0xYourDeployedAddress`
OKXDexAdapter: `0xYourDeployedAddress`
```

### **2. Configure OKX Router**

```bash
# Base
cast send $OKX_ADAPTER_BASE "setOKXRouter(address)" $OKX_ROUTER_BASE \
  --private-key $PRIVATE_KEY \
  --rpc-url base

# Polygon
cast send $OKX_ADAPTER_POLYGON "setOKXRouter(address)" $OKX_ROUTER_POLYGON \
  --private-key $PRIVATE_KEY \
  --rpc-url polygon

# Arbitrum
cast send $OKX_ADAPTER_ARBITRUM "setOKXRouter(address)" $OKX_ROUTER_ARBITRUM \
  --private-key $PRIVATE_KEY \
  --rpc-url arbitrum
```

### **3. Verify Configuration**

```bash
# Check OKX Router configured
cast call $OKX_ADAPTER_ADDRESS "okxRouter()(address)"

# Check TokenSwapperV3 features enabled
cast call $TOKENSWAPPER_V3 "okxIntegrationEnabled()(bool)"
cast call $TOKENSWAPPER_V3 "splitSwapEnabled()(bool)"
cast call $TOKENSWAPPER_V3 "oracleValidationEnabled()(bool)"

# Check Gateway authorized
cast call $TOKENSWAPPER_V3 "authorizedCallers(address)(bool)" $GATEWAY_ADDRESS
```

---

## 📊 Deployed Contract Addresses

### **Base**
| Contract | Address | Status |
|----------|---------|--------|
| TokenSwapperV3 | _Deployed Address_ | ⏳ Pending |
| OKXDexAdapter | _Deployed Address_ | ⏳ Pending |
| OKX Router | _Verify from OKX_ | ⏳ Pending |

### **Polygon**
| Contract | Address | Status |
|----------|---------|--------|
| TokenSwapperV3 | _Deployed Address_ | ⏳ Pending |
| OKXDexAdapter | _Deployed Address_ | ⏳ Pending |
| OKX Router | _Verify from OKX_ | ⏳ Pending |

### **Arbitrum**
| Contract | Address | Status |
|----------|---------|--------|
| TokenSwapperV3 | _Deployed Address_ | ⏳ Pending |
| OKXDexAdapter | _Deployed Address_ | ⏳ Pending |
| OKX Router | _Verify from OKX_ | ⏳ Pending |

---

## ⚠️ Troubleshooting

### **Issue: OKX Router address unknown**

**Solution:**
1. Deploy dengan `address(0)` (current setup)
2. Contact OKX support untuk router address
3. Configure via `setOKXRouter()` setelah dapat address

### **Issue: Token registration fails**

**Solution:**
Token registration di-comment out karena requires owner access.
Manual registration via:
```bash
cast send $REGISTRY_ADDRESS "setTokenSupport(address,bool)" $TOKEN_ADDRESS true \
  --private-key $OWNER_PRIVATE_KEY \
  --rpc-url $RPC_URL
```

### **Issue: Oracle configuration fails**

**Solution:**
Check Chainlink oracle addresses untuk chain yang sesuai:
- Base: https://docs.chain.link/data-feeds/price-feeds/addresses?network=base
- Polygon: https://docs.chain.link/data-feeds/price-feeds/addresses?network=polygon
- Arbitrum: https://docs.chain.link/data-feeds/price-feeds/addresses?network=arbitrum

---

## 📞 Support

For issues or questions:
- Check deployment logs
- Verify contract addresses on block explorer
- Contact development team

---

**Document Version:** 1.0  
**Last Updated:** 2026-03-29  
**Status:** ✅ READY FOR DEPLOYMENT
