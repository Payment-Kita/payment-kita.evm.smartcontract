# CHAIN ARBITRUM
Last updated: 2026-03-20 04:10 UTC
Deployment method: `make deploy-arbitrum-verify`
Status: final runtime active; latest gateway patch live and verified; latest Stargate sender/receiver live and verified; Stargate cross-token canary final pass
Authoritative runtime state is listed in the top sections of this file; lower sections retain historical rollout notes where relevant.

## Core Contracts (V2 Modular)
TokenRegistry: `0x53f1e35fea4b2cdc7e73feb4e36365c88569ebf0`
PaymentKitaVault: `0x4a92d4079853c78df38b4bbd574aa88679adef93`
PaymentKitaRouter: `0x3722374b187e5400f4423dbc45ad73784604d275`
PaymentKitaGateway: `0x256F96f965eb536E0d6684b0BC52a300663f505a`
Previous active gateway: `0x259294aecdc0006b73b1281c30440a8179cff44c`

## Gateway Runtime Modules
GatewayValidatorModule: `0xaf65342c8d1b42650b88d737ce5b630f5487f7f0`
GatewayQuoteModule: `0x6917d003add05eef125f3630fdae759c47f308bb`
GatewayExecutionModule: `0x62763108cd44c86c9b588f4defc2c66790fef34b`
GatewayPrivacyModule: `0x678fa4e50ed898e2c5694399651ea80894164766`
StealthEscrowFactory: `0x703d53d548ef860902057226079bc842bf077d1c`
FeeStrategyDefaultV1: `0x62ccb9fbbd975d41210b367f5bc1b6da00f71610`
FeePolicyManager: `0x5bd6093f455534dfd5c0220f5ba6660d5dbb30a8`

## Swapper + Adapters
- **TokenSwapper**: `0xD12200745Fbb85f37F439DC81F5a649FF131C675` ✅ **VERIFIED**
  - **Compiler**: v0.8.20+commit.a1b79de6
  - **Optimization**: 200 runs
  - **Deployed**: 2026-03-19 (Redeployed to fix verification + V4 pool config)
  - **Wiring Status**: ✅ Gateway → Vault → Swapper all connected
  - **Old Address**: `0x0B482Cc728A9AAf9BfBFDD24247B181aF0238295` (deprecated, unverified, DO NOT USE)
CCIPSender: `0x5cce8cdfb77dccd28ed7cf0acf567f92d737abd9`
CCIPReceiverAdapter: `0x2eF4D58457247A2e2cdB901bc0133EE3d434C657`
HyperbridgeSender: `0x7Fb1C521937eCEeBE9E86085d7F43A0Cdd36aFDA`
HyperbridgeReceiver: `0xF46C1fCff7E42bACF3b769C2364ffb86Ca52FCF6` (Redeployed 2026-03-17)
Deauthorized HTG Receiver: `0x6AEA896bFa65aC62cEc7C59A083B171A4948eB41`
StargateSenderAdapter: `0x2843e9880D7a29499e025C6E4ce749f127f6bD8e`
StargateReceiverAdapter active runtime: `0xA0502C041AAE8Ae1A4141D7E7937b34A01510fcf`
StargateReceiverAdapter previous runtime: `0xFE5fA0d938Eeb2aaEF18B8B8D910763234961ABd`

## Final Runtime Verification + Wiring
- `PaymentKitaGateway 0x256F...`: Pass - Verified
- `StargateSenderAdapter 0x2843...`: Already verified
- `StargateReceiverAdapter 0xA050...`: Already verified
- `CCIPReceiverAdapter 0x2eF4...`: Already verified
- `HyperbridgeTokenGatewaySender 0x7Fb1...`: Already verified
- `gateway.isAuthorizedAdapter(...)`:
  - `CCIPReceiver 0x2eF4D58457247A2e2cdB901bc0133EE3d434C657 = true`
  - `HTGReceiver 0xF46C1fCff7E42bACF3b769C2364ffb86Ca52FCF6 = true`
  - `StargateReceiver 0xA0502C041AAE8Ae1A4141D7E7937b34A01510fcf = true`
- `vault.authorizedSpenders(...)`:
  - `Gateway 0x256F96f965eb536E0d6684b0BC52a300663f505a = true`
  - `HTGSender 0x7Fb1C521937eCEeBE9E86085d7F43A0Cdd36aFDA = true`
  - `StargateSender 0x2843e9880D7a29499e025C6E4ce749f127f6bD8e = true`
- `swapper.authorizedCallers(0x256F96f965eb536E0d6684b0BC52a300663f505a) = true`
- `defaultBridgeTypes`:
  - `eip155:8453 -> 2`
  - `eip155:137 -> 2`

Cross-token Stargate canary final on `2026-03-20`:
- `A` Base -> Arbitrum regular `IDRX -> USDT`
  - destination on Arbitrum settled: `0x37`
- `F` Polygon -> Arbitrum regular `USDT -> USDT`
  - source tx `0x7560a95b4e53f6673b5a2a363258cc40d7ed2a2f3cac32934cc2359ed26401d5`
  - destination on Arbitrum settled: `0x3e4`
- `G` Base -> Arbitrum privacy `IDRX -> USDT`
  - source tx `0x4c999b0a5d913d58351aa9a1f0b9ed09cd745756db5b2e07364367ff7778d977`
  - settled on Arbitrum: `0x37`
  - `privacyForwardCompleted = true`
- `L` Polygon -> Arbitrum privacy `USDT -> USDT`
  - source tx `0xa16e23391abbe2726956e7adf9c8b11844ef332f4f10030d6bbfbf36fee14efb`
  - settled on Arbitrum: `0x3e4`
  - `privacyForwardCompleted = true`
- Arbitrum receiver USDC balance after rerun: `0`
- Arbitrum stealth USDT balance after rerun: `0`

## CCIP Route Status (Arbitrum <-> Base)
CCIP sender kept live: `0x5cce8cdfb77dccd28ed7cf0acf567f92d737abd9`
Current live receiver on Arbitrum: `0x2eF4D58457247A2e2cdB901bc0133EE3d434C657`
Patch status:
- Canonical token mismatch fix landed in `src/integrations/ccip/CCIPReceiver.sol`
- Validated locally in adapter tests: `31/31 PASS`
- Live receiver rewire broadcast: complete on `2026-03-15`
- Kept Base-side sender now points to Arbitrum receiver `0x2eF4D58457247A2e2cdB901bc0133EE3d434C657`
Operational note:
- `CCIP` is not yet approved as official fallback for `Arbitrum <-> Base`
- prior failed canary messages were generated against the old receiver logic and must be re-tested against the new live receiver

## Hyperbridge Token Gateway Route Status (Arbitrum <-> Base)
HTG sender (Arbitrum -> Base) after timeout rollout `2026-03-14`: `0x7Fb1C521937eCEeBE9E86085d7F43A0Cdd36aFDA`
HTG receiver (Base -> Arbitrum settlement executor peer): `0xF46C1fCff7E42bACF3b769C2364ffb86Ca52FCF6`
Deauthorized HTG receiver: `0x6AEA896bFa65aC62cEc7C59A083B171A4948eB41`
Remote HTG receiver (Base): `0x4511848F91Fd0f5F164FfBEf2e1c8BDE24a107a3`
Token gateway host: `0xFd413e3AFe560182C4471F4d143A96d3e259B6dE`
Active route timeout:
- `eip155:8453 -> 10800` on remote sender
- `eip155:42161 -> 14400`
Verification:
- HTG sender unit tests: `12/12 PASS`
- HTG receiver unit tests: `8/8 PASS`
- Direct HTG reference transfers supplied by operator completed in both directions

## Stargate Migration Status
Stargate sender deployed on Arbitrum: `0x2843e9880D7a29499e025C6E4ce749f127f6bD8e`
Stargate receiver active on Arbitrum: `0xA0502C041AAE8Ae1A4141D7E7937b34A01510fcf` (RescuableAdapter V2)
Stargate receiver previous runtime on Arbitrum: `0xFE5fA0d938Eeb2aaEF18B8B8D910763234961ABd`
USDC pool: `0xe8CDF27AcD73a434D661C84887215F7598e7d0d3`
Migration state:
- Full-mesh dry-run including `Arbitrum <-> Base` and `Arbitrum <-> Polygon`: pass
- Live full-mesh cutover broadcast: complete on `2026-03-15`
- Legacy LayerZero deauthorization broadcast: complete on `2026-03-15`
- Gateway default bridge now reads:
  - `eip155:8453 -> 2`
  - `eip155:137 -> 2`
- Live readback:
  - `gateway.isAuthorizedAdapter(0x0c6c2cc9c2fb42d2fe591f2c3fee4db428090ad4) = false`
  - `vault.authorizedSpenders(0x0c6c2cc9c2fb42d2fe591f2c3fee4db428090ad4) = false`
  - `vault.authorizedSpenders(0x64505be2844d35284ab58984f93dceb21bc77464) = false`
- Live route readback on `2026-03-19` after V2 cutover:
  - `Arbitrum -> Base` destination adapter: `0x000000000000000000000000e09ed3d37ac311f9ef4acf8927c27495cc0d291a`
  - `Arbitrum -> Polygon` destination adapter: `0x0000000000000000000000001808bd03899c80d3c9619ad9740e8db04f32b471`
  - Arbitrum receiver active source routes now terminate on `0xA0502C041AAE8Ae1A4141D7E7937b34A01510fcf`
  - Arbitrum gateway adapter auth:
    - old `0xFE5fA0d938Eeb2aaEF18B8B8D910763234961ABd = false`
    - new `0xA0502C041AAE8Ae1A4141D7E7937b34A01510fcf = true`
- Live sender-only privacy patch broadcast: complete on `2026-03-19`
  - Arbitrum sender runtime replaced with `0x2843e9880D7a29499e025C6E4ce749f127f6bD8e`
  - Arbitrum router `bridgeType=2` should now resolve through sender `0x2843e9880D7a29499e025C6E4ce749f127f6bD8e`
- Privacy canary rerun on `2026-03-19` captured the intermediate failure stage before compose gas was raised and stealth forwarders were restored.
- That note is now superseded by the final `2026-03-20` cross-token rerun above.
- direct `LayerZero` contracts remain deployed only as historical artifacts; runtime authorization is removed

## Registered Tokens (TokenRegistry)
Bridge token / USDC: `0xaf88d065e77c8cC2239327C5EDb3A432268e5831` (decimals 6)
USDT: `0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9` (decimals 6)
DAI: `0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1` (decimals 18)
WBTC: `0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f` (decimals 8)
XAUT: `0x40461291347e1eCbb09499F3371D3f17f10d7159` (decimals 6)
XSGD: `0xE333e7754a2DC1E020a162Ecab019254b9DaB653` (decimals 6)
MYRC: `0x3eD03E95DD894235090B3d4A49E0C3239EDcE59e` (decimals 18)

## Swapper Route Configuration

### V4 Direct Pools (Uniswap V4 - Available on Arbitrum ✅)
| Pool | Fee | TickSpacing | Pair Key Hash | Pool ID | Status |
|------|-----|-------------|---------------|---------|--------|
| USDC/USDT | 100 | 1 | `0x4752d296...` | - | ✅ Active |
| USDC/WBTC | 500 | 10 | `0x...` | - | ✅ Active |
| USDT/WBTC | 500 | 10 | `0x...` | - | ✅ Active |
| **XAUT/USDT** | **6000** | **120** | `0xc9719331b492bc5508393fc6ea1c210ef0f39bf8fb784b69450e8ea312da64d4` | `0xb896675bfb20eed4b90d83f64cf137a860a99a86604f7fac201a822f2b4abc34` | ✅ **Reconfigured 2026-03-19** |

⚠️ **IMPORTANT**: V4 pools require correct pair key hash computation: `keccak256(abi.encodePacked(token0, token1))` where token0 < token1 (sorted).

### V3 Fallback Pools (Uniswap V3)
| Pool | Fee | Status |
|------|-----|--------|
| USDC/DAI | 100 | ✅ Available |
| USDT/DAI | 100 | ✅ Available |

### Multi-Hop Routes
- DAI -> USDC -> USDT -> XAUT
- XAUT -> USDT -> USDC -> DAI
- WBTC -> USDC -> USDT -> XAUT
- XAUT -> USDT -> USDC -> WBTC

### Uniswap V4 Deployment Addresses (Arbitrum)
- **PoolManager**: `0x360e68faccca8ca495c1b759fd9eee466db9fb32`
- **Universal Router**: `0xa51afafe0263b40edaef0df8781ea9aa03e381a3`
- **Quoter**: `0x3972c00f7ed4885e145823eb7c655375d275a1c5`

Source: https://docs.uniswap.org/contracts/v4/deployments

## Historical Summary
- `2026-03-15`: Stargate full-mesh cutover completed
- `2026-03-19`: sender-only privacy patch deployed
- `2026-03-20`: cross-token Stargate final rerun passed

## Explorer References
Gateway: `https://arbiscan.io/address/0x256f96f965eb536e0d6684b0bc52a300663f505a`
TokenRegistry: `https://arbiscan.io/address/0x53f1e35fea4b2cdc7e73feb4e36365c88569ebf0`
TokenSwapper: `https://arbiscan.io/address/0xD12200745Fbb85f37F439DC81F5a649FF131C675`
