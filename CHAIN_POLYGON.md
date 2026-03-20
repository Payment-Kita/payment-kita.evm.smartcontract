# CHAIN POLYGON
Last updated: 2026-03-20 04:10 UTC
Deployment method: `make deploy-polygon-verify-fallback` (resume across RPC)
Status: final runtime active; latest gateway patch live and verified; latest Stargate sender/receiver live and verified; Stargate cross-token canary final pass; legacy direct LayerZero deauthorized
Authoritative runtime state is listed in the top sections of this file; lower sections retain historical rollout notes where relevant.

## Core Contracts (V2 Modular)
TokenRegistry: `0x01e0042BC84F1dbc2F88Fb3ae8b1EA6A86Dc491d`
PaymentKitaVault: `0x28ee150c1F23952cFe01B38612c4D45E28FDA4A3`
PaymentKitaRouter: `0x84ff4D31f24110dB00a9d7F51B104fD7D6b3bF0F`
PaymentKitaGateway: `0xC2Df6CbFeA8c00f7Dacf08B27124cC4fB72f3B69`
Previous active gateway: `0xcb5fC6c5E7895406b797B11F91AF67A07027a26F`

## Gateway Runtime Modules
GatewayValidatorModule: `0x0EBEB5e73e1794e63849e502cDc8ffc275e2e7b3`
GatewayQuoteModule: `0xe7F4428ECD9F1f1a6E4D5E34614e3d98E5388F04`
GatewayExecutionModule: `0xAf32bC428C6FBace6b0d1d3Fb8C5c3A78f201694`
GatewayPrivacyModule: `0x78Af3584F11af9E853F8CDefa3DeD4B464C837d0`
StealthEscrowFactory: `0xa73Ed3306186f7DA4204fD59e8c7dE8888D16Fc5`
FeeStrategyDefaultV1: `0x538f7690b6d19AD503917BaF4D71cb0D07400934`
FeePolicyManager: `0x7700B7d551f6195F6C6a60AE0c7B8fA8e5eEF608`

## Swapper + Adapters
TokenSwapper: `0xe50BDD9CA4289CfD675240B3A7294035655AF8d2`
CCIPSender: `0xccA8474dF6D534C6E5ddC928D108747E4C6fD65A`
CCIPReceiverAdapter: `0x10892efc8621D5ecb1de83d2Fd89F36bb4FBC70d`
HyperbridgeSender: `0xF44019b4f5B08dA0960087Ad4290a0376580Aed1`
HyperbridgeReceiver: `0xF32e1F744A37a99d55A892905B8018d8f6b1cb99`
LayerZeroSenderAdapter: `0x4b88661B2b1e3772FDDfe4dfEAB21372b7650aC4`
LayerZeroReceiverAdapter: `0x244A2Cb45A531d42A1177d06aDb01184125c43B8`
StargateSenderAdapter: `0x8B6c7770D4B8AaD2d600e0cf5df3Eea5Bc0EB0fe`
StargateReceiverAdapter active runtime: `0x1808bD03899C80D3C9619AD9740E8db04F32b471` (RescuableAdapter V2)
StargateReceiverAdapter previous runtime: `0x5098Df68C5935c923CD551649C74725989bDc3DC`

## Final Runtime Verification + Wiring
- `PaymentKitaGateway 0xC2Df...`: Pass - Verified
- `StargateSenderAdapter 0x8B6c...`: Already verified
- `StargateReceiverAdapter 0x1808...`: Already verified
- `gateway.isAuthorizedAdapter(...)`:
  - `CCIPReceiver 0x10892efc8621D5ecb1de83d2Fd89F36bb4FBC70d = true`
  - `HTGReceiver 0xF32e1F744A37a99d55A892905B8018d8f6b1cb99 = true`
  - `StargateReceiver 0x1808bD03899C80D3C9619AD9740E8db04F32b471 = true`
- `vault.authorizedSpenders(...)`:
  - `Gateway 0xC2Df6CbFeA8c00f7Dacf08B27124cC4fB72f3B69 = true`
  - `StargateSender 0x8B6c7770D4B8AaD2d600e0cf5df3Eea5Bc0EB0fe = true`
- `defaultBridgeTypes`:
  - `eip155:8453 -> 2`
  - `eip155:42161 -> 2`

Cross-token Stargate canary final on `2026-03-20`:
- `B` Base -> Polygon regular `IDRX -> USDT`
  - destination on Polygon settled: `0x37`
- `H` Base -> Polygon privacy `IDRX -> USDT`
  - source tx `0xa718c4c785f2347ba5366d19e7234b7534cc7fab521b82d407a063d6d364acd6`
  - settled on Polygon: `0x37`
  - `privacyForwardCompleted = true`
- `J` Arbitrum -> Polygon privacy `USDT -> USDT`
  - source tx `0xb5156060241bc85e7e104e44c2ea78479635e423db59ee15feb8c4d64b121686`
  - settled on Polygon: `0x3e4`
  - `privacyForwardCompleted = true`
- Polygon receiver USDC balance after rerun: `0`
- Polygon stealth USDT balance after rerun: `0`

## Stargate Migration Status
USDC pool: `0x9Aa02D4Fae7F58b8E8f34c66E756cC734DAc7fe4`
Target lanes:
- `Base <-> Polygon`
- `Arbitrum <-> Polygon`
Migration state:
- full-mesh dry-run across `Base`, `Arbitrum`, `Polygon`: pass
- Polygon Stargate adapters are deployed
- live full-mesh cutover broadcast: complete on `2026-03-15`
- legacy LayerZero deauthorization broadcast: complete on `2026-03-15`
- Gateway default bridge now reads:
  - `eip155:8453 -> 2`
  - `eip155:42161 -> 2`
- `Hyperbridge` is not the target normal path for Polygon USDC lanes
- Live readback:
  - `gateway.isAuthorizedAdapter(0x244A2Cb45A531d42A1177d06aDb01184125c43B8) = false`
  - `vault.authorizedSpenders(0x244A2Cb45A531d42A1177d06aDb01184125c43B8) = false`
- Live route readback on `2026-03-19` after V2 cutover:
  - `Polygon -> Base` destination adapter: `0x000000000000000000000000e09ed3d37ac311f9ef4acf8927c27495cc0d291a`
  - `Polygon -> Arbitrum` destination adapter: `0x000000000000000000000000a0502c041aae8ae1a4141d7e7937b34a01510fcf`
  - Polygon receiver active source routes now terminate on `0x1808bD03899C80D3C9619AD9740E8db04F32b471`
  - Polygon gateway adapter auth:
    - old `0x5098Df68C5935c923CD551649C74725989bDc3DC = false`
    - new `0x1808bD03899C80D3C9619AD9740E8db04F32b471 = true`
  - `vault.authorizedSpenders(0x4b88661B2b1e3772FDDfe4dfEAB21372b7650aC4) = false`
- Live sender-only privacy patch broadcast: complete on `2026-03-19`
  - Polygon sender runtime replaced with `0x8B6c7770D4B8AaD2d600e0cf5df3Eea5Bc0EB0fe`
  - Polygon router `bridgeType=2` readback:
    - `eip155:8453 -> 0x8B6c7770D4B8AaD2d600e0cf5df3Eea5Bc0EB0fe`
    - `eip155:42161 -> 0x8B6c7770D4B8AaD2d600e0cf5df3Eea5Bc0EB0fe`
- Privacy rescue + verification on `2026-03-19`
  - Polygon stealth escrow rescued:
    - `setForwarder`: `0x63ce173c09bae63c8bd6fe0e53cbe8eb37b2e68481f649b3dacda7f9fb18d5d6`
    - `forwardToken`: `0xb51a63e4eea81a1a5af7179fc1f0eac397e2ec4bc77857210c1ad96378a9da44`
  - Polygon-side stealth escrow balance after rescue and new privacy canary: `0`
  - Privacy canary source tx:
    - `Polygon -> Base`: `0xa7b30a17164a4eb87060d2eeda2cf4ff6730686a8f33aa897e76e26868e49d85`
- direct `LayerZero` contracts remain deployed only as historical artifacts; runtime authorization is removed

## Registered Tokens (TokenRegistry)
Bridge token / USDC: `0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359` (decimals 6)
IDRT: `0x554cd6bdD03214b10AafA3e0D4D42De0C5D2937b` (decimals 2)
USDT: `0xc2132D05D31c914a87C6611C10748AEb04B58e8F` (decimals 6)
WETH: `0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619` (decimals 18)
DAI: `0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063` (decimals 18)
XSGD: `0xDC3326e71D45186F113a2F448984CA0e8D201995` (decimals 6)

## Swapper V3 Configuration
V3 Router: `0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45`
Pool USDC/USDT fee 100
Pool USDC/WETH fee 500
Pool USDC/DAI fee 100
Pool IDRT/USDC fee 500

## Privacy + Wiring Readiness
Gateway privacy module wired: PASS
Privacy module authorized gateway: PASS
Vault authorized spender gateway + swapper: PASS
Swapper authorized caller gateway: PASS
Gateway authorized adapters: active receivers only; legacy LayerZero receiver deauthorized
Documentation note:
- Stargate cutover and legacy LayerZero deauthorization are now reflected in this file

## Historical Summary
- `2026-03-15`: Stargate full-mesh cutover completed
- `2026-03-19`: sender-only privacy patch deployed
- `2026-03-20`: cross-token Stargate final rerun passed

## Explorer References
Gateway: `https://polygonscan.com/address/0xc2df6cbfea8c00f7dacf08b27124cc4fb72f3b69`
TokenRegistry: `https://polygonscan.com/address/0x01e0042BC84F1dbc2F88Fb3ae8b1EA6A86Dc491d`
TokenSwapper: `https://polygonscan.com/address/0xe50BDD9CA4289CfD675240B3A7294035655AF8d2`
