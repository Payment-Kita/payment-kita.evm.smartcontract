# CHAIN POLYGON
Last updated: 2026-03-15
Deployment method: `make deploy-polygon-verify-fallback` (resume across RPC)
Status: on-chain runtime active; Stargate cutover live; legacy LayerZero deauthorized

## Core Contracts (V2 Modular)
TokenRegistry: `0x01e0042BC84F1dbc2F88Fb3ae8b1EA6A86Dc491d`
PaymentKitaVault: `0x28ee150c1F23952cFe01B38612c4D45E28FDA4A3`
PaymentKitaRouter: `0x84ff4D31f24110dB00a9d7F51B104fD7D6b3bF0F`
PaymentKitaGateway: `0xcb5fC6c5E7895406b797B11F91AF67A07027a26F`

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
StargateSenderAdapter: `0x838Ba4E44E24f4d9A655698df535F404448aA2A9`
StargateReceiverAdapter: `0x1808bD03899C80D3C9619AD9740E8db04F32b471` (RescuableAdapter V2)

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
  - `vault.authorizedSpenders(0x4b88661B2b1e3772FDDfe4dfEAB21372b7650aC4) = false`
- direct `LayerZero` contracts remain deployed only as historical artifacts; runtime authorization is removed

## Registered Tokens (TokenRegistry)
Bridge token / USDC: `0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359` (decimals 6)
IDRT: `0x554cd6bdD03214b10AafA3e0D4D42De0C5D2937b` (decimals 2)
USDT: `0xc2132D05D31c914a87C6611C10748AEb04B58e8F` (decimals 6)
WETH: `0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619` (decimals 18)
DAI: `0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063` (decimals 18)

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

## Explorer References
Gateway: `https://polygonscan.com/address/0xcb5fC6c5E7895406b797B11F91AF67A07027a26F`
TokenRegistry: `https://polygonscan.com/address/0x01e0042BC84F1dbc2F88Fb3ae8b1EA6A86Dc491d`
TokenSwapper: `https://polygonscan.com/address/0xe50BDD9CA4289CfD675240B3A7294035655AF8d2`
