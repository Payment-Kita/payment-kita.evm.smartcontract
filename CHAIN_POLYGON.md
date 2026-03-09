# DEPLOYMENT CONTRACT
TokenRegistry deployed at: 0xd2C69EA4968e9F7cc8C0F447eB9b6DFdFFb1F8D7
PaymentKitaVault deployed at: 0x6CFc15C526B8d06e7D192C18B5A2C5e3E10F7D8c
PaymentKitaRouter deployed at: 0xb4a911eC34eDaaEFC393c52bbD926790B9219df4
PaymentKitaGateway deployed at: 0x7a4f3b606D90e72555A36cB370531638fad19Bf8
TokenSwapper deployed at: 0xF043b0b91C8F5b6C2DC63897f1632D6D15e199A9
CCIPSender deployed at: 0xdf6c1dFEf6A16315F6Be460114fB090Aea4dE500
CCIPReceiverAdapter deployed at: 0xbC75055BdF937353721BFBa9Dd1DCCFD0c70B8dd
HyperbridgeSender deployed at: 0xeC25Af21e16aD82eD7060DcC90a1D07255253e28 (Verified)
HyperbridgeReceiver deployed at: 0x86b15744F1CC682e8a7236Bb7B2d02dA957958aD
LayerZeroSenderAdapter deployed at: 0xCC37C9AF29E58a17AE1191159B4BA67f56D1Bd1e
LayerZeroReceiverAdapter deployed at: 0x67AAc121bc447F112389921A8B94c3D6FCBd98f9

# AUTHORIZED TOKEN
Registered bridge token as supported: 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359
Registered POLYGON_USDC: 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359
Registered POLYGON_USDT: 0xc2132D05D31c914a87C6611C10748AEb04B58e8F
Registered POLYGON_WETH: 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619
Registered POLYGON_DAI: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063

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

PRIVACY_GATE_GATEWAY=<POLYGON_GATEWAY> \
PRIVACY_GATE_VAULT=<POLYGON_VAULT> \
PRIVACY_GATE_SWAPPER=<POLYGON_SWAPPER> \
PRIVACY_GATE_PRIVACY_MODULE=<POLYGON_PRIVACY_MODULE> \
BASE_RPC_URL=$POLYGON_RPC_URL \
make validate-privacy-route-gate PRIVACY_GATE_SKIP_TESTS=1
```
