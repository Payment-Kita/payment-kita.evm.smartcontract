# Backup & Reset Plan - TokenSwapper Recovery

## 📋 Overview

Scripts ini digunakan untuk **RESET** kembali ke TokenSwapper yang lama jika deployment OKX Adapter bermasalah.

---

## 🔒 BACKUP CURRENT STATE

### **Current TokenSwapper Addresses:**

| Chain | TokenSwapper Address | Gateway Address |
|-------|---------------------|-----------------|
| **Base** | `0x8B6c7770D4B8AaD2d600e0cf5df3Eea5Bc0EB0fe` | `0xc1d4Ed499417B560A5Df53bA5e2b1A54755Ce58C` |
| **Polygon** | `0xe50BDD9CA4289CfD675240B3A7294035655AF8d2` | `0xC2Df6CbFeA8c00f7Dacf08B27124cC4fB72f3B69` |
| **Arbitrum** | `0xD12200745Fbb85f37F439DC81F5a649FF131C675` | `0x256F96f965eb536E0d6684b0BC52a300663f505a` |

**SAVE THESE ADDRESSES!** Ini adalah fallback jika deployment baru gagal.

---

## 🚨 EMERGENCY RESET SCRIPTS

### **Option 1: Quick Reset (Recommended)**

Jika OKX Adapter bermasalah, cukup **disable** OKX integration:

```bash
# Base
cast send $OKX_ADAPTER_ADDRESS "setOKXIntegrationEnabled(bool)" false \
  --private-key $PRIVATE_KEY \
  --rpc-url base

# Polygon
cast send $OKX_ADAPTER_ADDRESS "setOKXIntegrationEnabled(bool)" false \
  --private-key $PRIVATE_KEY \
  --rpc-url polygon

# Arbitrum
cast send $OKX_ADAPTER_ADDRESS "setOKXIntegrationEnabled(bool)" false \
  --private-key $PRIVATE_KEY \
  --rpc-url arbitrum
```

**Effect:** OKX integration disabled, system kembali ke TokenSwapper lama.

---

### **Option 2: Full Reset (Remove OKX Adapter)**

Jika ingin **completely remove** OKX Adapter:

**Step 1: Revoke Gateway authorization**
```bash
# Base
cast send $TOKENSWAPPER_V3_ADDRESS "setAuthorizedCaller(address,bool)" $GATEWAY_ADDRESS false \
  --private-key $PRIVATE_KEY \
  --rpc-url base

# Polygon
cast send $TOKENSWAPPER_V3_ADDRESS "setAuthorizedCaller(address,bool)" $GATEWAY_ADDRESS false \
  --private-key $PRIVATE_KEY \
  --rpc-url polygon

# Arbitrum
cast send $TOKENSWAPPER_V3_ADDRESS "setAuthorizedCaller(address,bool)" $GATEWAY_ADDRESS false \
  --private-key $PRIVATE_KEY \
  --rpc-url arbitrum
```

**Step 2: Re-authorize old TokenSwapper (if needed)**
```bash
# Base
cast send $GATEWAY_ADDRESS "setTokenSwapper(address)" $OLD_TOKENSWAPPER_ADDRESS \
  --private-key $PRIVATE_KEY \
  --rpc-url base

# Polygon
cast send $GATEWAY_ADDRESS "setTokenSwapper(address)" $OLD_TOKENSWAPPER_ADDRESS \
  --private-key $PRIVATE_KEY \
  --rpc-url polygon

# Arbitrum
cast send $GATEWAY_ADDRESS "setTokenSwapper(address)" $OLD_TOKENSWAPPER_ADDRESS \
  --private-key $PRIVATE_KEY \
  --rpc-url arbitrum
```

---

## 📝 VERIFICATION

Setelah reset, verify:

```bash
# Check OKX integration disabled
cast call $OKX_ADAPTER_ADDRESS "integrationEnabled()(bool)"
# Expected: false

# Check Gateway authorized on old TokenSwapper
cast call $OLD_TOKENSWAPPER_ADDRESS "authorizedCallers(address)(bool)" $GATEWAY_ADDRESS
# Expected: true

# Test swap (should use old TokenSwapper)
# ... perform test swap ...
```

---

## 🔄 ROLLBACK DECISION TREE

```
Deployment Issue Detected
         |
         v
┌────────────────────┐
│ Is it critical?    │
└────────────────────┘
         |
    +----+----+
    |         |
   NO        YES
    |         |
    v         v
Continue  Disable OKX
          Integration
                |
                v
         ┌──────────────────┐
         │ Does it work?    │
         └──────────────────┘
                |
           +----+----+
           |         |
          YES       NO
           |         |
           v         v
      Continue   Full Reset
      with OKX   to Old TS
```

---

## 📞 CONTACT

Jika ada masalah saat reset:
- Check deployment logs
- Verify contract addresses on block explorer
- Contact development team

---

**Document Version:** 1.0  
**Last Updated:** 2026-03-29  
**Status:** ✅ READY FOR EMERGENCY USE
