# DEPLOYMENT CONTRACT
TokenRegistry deployed at: 0xFA311B3C424649334b2110163f361A496D1c87fd
PaymentKitaVault deployed at: 0x12306CA381813595BeE3c64b19318419C9E12f02
PaymentKitaRouter deployed at: 0x5CF8c2EC1e96e6a5b17146b2BeF67d1012deEF7e
PaymentKitaGateway deployed at: 0x5a1179675aaE10D8E4B74d5Ff87152016f28F0D8
TokenSwapper deployed at: 0xD0f00F0D4b2daecdD96007A5a9c06B50caD4c935
CCIPSender deployed at: 0xC9126fACB9201d79EF860F7f4EF2037c69D80a56
CCIPReceiverAdapter deployed at: 0x0Fad39d945785b3d35B7C8a7aa856431c42B75f5
HyperbridgeSender deployed at: 0xce96998714d4f8701a3a45Cf6b4B8A361282D07c
HyperbridgeReceiver deployed at: 0x61E7EC10bB66042bb3D83f5E4Ba20398B1778BAF
LayerZeroSenderAdapter deployed at: 0x263a3a83755613c50Dc42329D9B7771d91D8c1c1
LayerZeroReceiverAdapter deployed at: 0x7A356d451157F2AE128AD6Bd21Aa77605fAae09c

# AUTHORIZED TOKEN
Registered bridge token as supported: 0xaf88d065e77c8cC2239327C5EDb3A432268e5831
Registered ARBITRUM_USDC: 0xaf88d065e77c8cC2239327C5EDb3A432268e5831
Registered ARBITRUM_USDT: 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9
Registered ARBITRUM_USDTO: 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9
Registered ARBITRUM_WETH: 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1

# PRIVACY READINESS MATRIX (PHASE 4)
Last updated: 2026-03-09

| Check | Expected | Current |
|---|---|---|
| Gateway privacy module wired | `gateway.privacyModule != 0x0` | Pending gate run |
| Privacy module authorize gateway | `authorizedGateway(gateway)=true` | Pending gate run |
| Vault authorize gateway/swapper | `authorizedSpenders(gateway|swapper)=true` | Pending gate run |
| Swapper authorize gateway caller | `authorizedCallers(gateway)=true` | Pending gate run |
| Adapter auth (gateway/vault/swapper) | CCIP/Hyperbridge/LZ receiver authorized | Pending gate run |
| Privacy quote probe | `quotePaymentCost + previewApproval` (mode privacy) no revert | Pending gate run |
| Privacy regression tests | Privacy suites pass | Pending gate run |

## Gate Command (Template)
```bash
cd payment-kita.evm.smartcontract
source .env

PRIVACY_GATE_GATEWAY=<ARBITRUM_GATEWAY> \
PRIVACY_GATE_VAULT=<ARBITRUM_VAULT> \
PRIVACY_GATE_SWAPPER=<ARBITRUM_SWAPPER> \
PRIVACY_GATE_PRIVACY_MODULE=<ARBITRUM_PRIVACY_MODULE> \
BASE_RPC_URL=$ARBITRUM_RPC_URL \
make validate-privacy-route-gate PRIVACY_GATE_SKIP_TESTS=1
```
