# DEPLOYMENT CONTRACT
TokenRegistry deployed at: 0x140fbAA1e8BE387082aeb6088E4Ffe1bf3Ba4d4f
PaymentKitaVault deployed at: 0x67d0af7f163F45578679eDa4BDf9042E3E5FEc60
PaymentKitaRouter deployed at: 0x1b91B56aD3aA6B35e5EAe18EE19A42574A545802
PaymentKitaGateway deployed at: 0xf0daa1a24556B68B4636FBE1c90dE326842A164C
TokenSwapper deployed at: 0x8B6c7770D4B8AaD2d600e0cf5df3Eea5Bc0EB0fe

Gateway modules wired:
- validator: 0x7e0072A1f8D8DCc77bdbB460887696350f02a17D
- quote: 0x5DD0151952788aEd9FDA22EB5407D861cB845483
- execution: 0x7Fb1C521937eCEeBE9E86085d7F43A0Cdd36aFDA
- privacy: 0x36cC070A24149BebB614898B5449641a6c3C5294
FeePolicyManager: 0x88bE1896C8FE10fCCbf8c568D9965454A44DCcc7
Default fee strategy: 0x43f5Efb8E4732ed6bdaA38f4B75c359fc876324B

CCIPSender deployed at: 0x47FEA6C20aC5F029BAB99Ec2ed756d94c54707DE
CCIPSender authorized caller (router): 0x1b91B56aD3aA6B35e5EAe18EE19A42574A545802
CCIPReceiverAdapter deployed at: 0x46FAc7ac7D89d2daE0B647F31888AdD01cEed2bb
HyperbridgeSender deployed at: 0xB9F0429D420571923EeC57E8b7025d063E361329
HyperbridgeReceiver deployed at: 0x2AD1ac009fAcc6528352d5ca23fd35F025C328f3
LayerZeroSenderAdapter deployed at: 0x11bfD843dCEbF421d2f2A07D2C8BA5Db85E501E9
LayerZeroReceiverAdapter deployed at: 0xc4c28aeeE5bb312970a7266461838565E1eEEc1a

# AUTHORIZED ROUTE PATH
Registered bridge token as supported: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
Configured IDRX/USDC V3 pool
Configured USDC/WETH V3 pool
Configured USDC/cbBTC V3 pool
Configured USDC/USDe V3 pool
Configured USDC -> cbBTC -> WBTC
Configured USDC -> WETH -> cbETH
Configured WBTC -> cbBTC -> USDC -> IDRX
Configured cbETH -> WETH -> USDC -> IDRX
Configured IDRX -> USDC -> WETH
Configured IDRX -> USDC -> USDe

# CCIP ROUTE STATUS (Base -> Polygon)
Route CAIP2: eip155:137
Bridge type: 1 (CCIP)
Sender chainSelector: 4051577828743386545
Sender destinationAdapter (Polygon receiver): pending re-validate after latest Base redeploy
Receiver sourceSelector trusted sender (Polygon sender): pending re-validate after latest Base redeploy
Gateway default bridge for eip155:137: 1 (CCIP)
Validation: re-run `make ccip-validate-dry`

# LAYERZERO ROUTE STATUS (Base -> Polygon)
Route CAIP2: eip155:137
Bridge type: 2 (LayerZero)
Sender dstEid: 30109
Sender dstPeer: pending re-validate after latest Base redeploy
Receiver srcEid: 30109
Receiver srcPeer: pending re-validate after latest Base redeploy
Validation: re-run `make lz-validate-dry`

# AUTHORIZED TOKEN
Registered bridge token as supported: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
Registered BASE_USDC: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
Registered BASE_USDE: 0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34
Registered BASE_WETH: 0x4200000000000000000000000000000000000006
Registered BASE_CBETH: 0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22
Registered BASE_CBBTC: 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf
Registered BASE_WBTC: 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c
Registered BASE_IDRX: 0x18Bc5bcC660cf2B9cE3cd51a404aFe1a0cBD3C22

# PRIVACY READINESS MATRIX (PHASE 4)
Last updated: 2026-03-09

| Check | Expected | Current |
|---|---|---|
| Gateway privacy module wired | `gateway.privacyModule != 0x0` | Configured (`0x36cC070A24149BebB614898B5449641a6c3C5294`) |
| Privacy module authorize gateway | `authorizedGateway(gateway)=true` | Configured (from deploy flow) |
| Vault authorize gateway/swapper | `authorizedSpenders(gateway|swapper)=true` | Configured (from deploy flow) |
| Swapper authorize gateway caller | `authorizedCallers(gateway)=true` | Configured (from deploy flow) |
| Adapter auth (gateway/vault/swapper) | CCIP/Hyperbridge/LZ receiver authorized | Configured (from deploy flow) |
| Privacy quote probe | `quotePaymentCost + previewApproval` (mode privacy) no revert | Pending runtime gate |
| Privacy regression tests | Privacy suites pass | Pending runtime gate |

## Gate Command (Base)
```bash
cd payment-kita.evm.smartcontract
source .env

PRIVACY_GATE_GATEWAY=0xf0daa1a24556B68B4636FBE1c90dE326842A164C \
PRIVACY_GATE_VAULT=0x67d0af7f163F45578679eDa4BDf9042E3E5FEc60 \
PRIVACY_GATE_SWAPPER=0x8B6c7770D4B8AaD2d600e0cf5df3Eea5Bc0EB0fe \
PRIVACY_GATE_PRIVACY_MODULE=0x36cC070A24149BebB614898B5449641a6c3C5294 \
PRIVACY_GATE_ADAPTER_CCIP=0x46FAc7ac7D89d2daE0B647F31888AdD01cEed2bb \
PRIVACY_GATE_ADAPTER_HYPERBRIDGE=0x2AD1ac009fAcc6528352d5ca23fd35F025C328f3 \
PRIVACY_GATE_ADAPTER_LAYERZERO=0xc4c28aeeE5bb312970a7266461838565E1eEEc1a \
PRIVACY_GATE_SOURCE_TOKEN=0x18Bc5bcC660cf2B9cE3cd51a404aFe1a0cBD3C22 \
PRIVACY_GATE_DEST_TOKEN=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913 \
PRIVACY_GATE_DEST_CAIP2=eip155:8453 \
PRIVACY_GATE_RECEIVER=0x2Bda11F04b8F96D361D2DBB1bA8c36B744B4b42A \
PRIVACY_GATE_AMOUNT=100000 \
make validate-privacy-route-gate
```
