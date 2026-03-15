# CHAIN ARBITRUM
Last updated: 2026-03-15
Deployment method: `make deploy-arbitrum-verify`
Status: on-chain runtime active; HTG runtime updated; CCIP patch verified locally; Stargate cutover live; legacy LayerZero deauthorized

## Core Contracts (V2 Modular)
TokenRegistry: `0x53f1e35fea4b2cdc7e73feb4e36365c88569ebf0`
PaymentKitaVault: `0x4a92d4079853c78df38b4bbd574aa88679adef93`
PaymentKitaRouter: `0x3722374b187e5400f4423dbc45ad73784604d275`
PaymentKitaGateway: `0x259294aecdc0006b73b1281c30440a8179cff44c`

## Gateway Runtime Modules
GatewayValidatorModule: `0xaf65342c8d1b42650b88d737ce5b630f5487f7f0`
GatewayQuoteModule: `0x6917d003add05eef125f3630fdae759c47f308bb`
GatewayExecutionModule: `0x62763108cd44c86c9b588f4defc2c66790fef34b`
GatewayPrivacyModule: `0x678fa4e50ed898e2c5694399651ea80894164766`
StealthEscrowFactory: `0x703d53d548ef860902057226079bc842bf077d1c`
FeeStrategyDefaultV1: `0x62ccb9fbbd975d41210b367f5bc1b6da00f71610`
FeePolicyManager: `0x5bd6093f455534dfd5c0220f5ba6660d5dbb30a8`

## Swapper + Adapters
TokenSwapper: `0x5d86bfd5a361bc652bc596dd2a77cd2bdba2bf35`
CCIPSender: `0x5cce8cdfb77dccd28ed7cf0acf567f92d737abd9`
CCIPReceiverAdapter: `0x0078f08c7a1c3dab5986f00dc4e32018a95ee195`
HyperbridgeSender: `0xfdc7986e73f91ebc08130ba2325d32b23f844e26`
HyperbridgeReceiver: `0x19b18176f3d3b177dd0f48843b94010d80ab4d42`
LayerZeroSenderAdapter: `0x64505be2844d35284ab58984f93dceb21bc77464`
LayerZeroReceiverAdapter: `0x0c6c2cc9c2fb42d2fe591f2c3fee4db428090ad4`

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
HTG receiver (Base -> Arbitrum settlement executor peer): `0x6AEA896bFa65aC62cEc7C59A083B171A4948eB41`
Remote HTG receiver (Base): `0x5649f75c6aD1140bbABed12978Ec27AdADE4E2d4`
Token gateway host: `0xFd413e3AFe560182C4471F4d143A96d3e259B6dE`
Active route timeout:
- `eip155:8453 -> 10800` on remote sender
- `eip155:42161 -> 14400`
Verification:
- HTG sender unit tests: `12/12 PASS`
- HTG receiver unit tests: `8/8 PASS`
- Direct HTG reference transfers supplied by operator completed in both directions

## Stargate Migration Status
Stargate sender deployed on Arbitrum: `0x64976A3cDE870507B269FD4A8aC2dC9993bc3F3A`
Stargate receiver deployed on Arbitrum: `0xFE5fA0d938Eeb2aaEF18B8B8D910763234961ABd`
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
- direct `LayerZero` contracts remain deployed only as historical artifacts; runtime authorization is removed

## Registered Tokens (TokenRegistry)
Bridge token / USDC: `0xaf88d065e77c8cC2239327C5EDb3A432268e5831` (decimals 6)
USDT: `0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9` (decimals 6)
DAI: `0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1` (decimals 18)
WBTC: `0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f` (decimals 8)
XAUT: `0x40461291347e1eCbb09499F3371D3f17f10d7159` (decimals 6)

## Swapper Route Configuration
V3 Router: `0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45`
V4 direct pool USDC/USDT fee 100 tick 1
V4 direct pool USDC/WBTC fee 500 tick 10
V4 direct pool USDT/WBTC fee 500 tick 10
V4 direct pool XAUT/USDT fee 500 tick 10
V3 pool USDC/DAI fee 100
V3 pool USDT/DAI fee 100
Multi-hop DAI -> USDC -> USDT -> XAUT
Multi-hop XAUT -> USDT -> USDC -> DAI
Multi-hop WBTC -> USDC -> USDT -> XAUT
Multi-hop XAUT -> USDT -> USDC -> WBTC

## Explorer References
Gateway: `https://arbiscan.io/address/0x259294aecdc0006b73b1281c30440a8179cff44c`
TokenRegistry: `https://arbiscan.io/address/0x53f1e35fea4b2cdc7e73feb4e36365c88569ebf0`
TokenSwapper: `https://arbiscan.io/address/0x5d86bfd5a361bc652bc596dd2a77cd2bdba2bf35`
