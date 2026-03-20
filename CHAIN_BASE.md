# CHAIN BASE
Last updated: 2026-03-20 04:10 UTC
Status: final runtime active; latest gateway patch live and verified; latest Stargate sender/receiver live and verified; Stargate cross-token canary final pass; legacy direct LayerZero deauthorized
Authoritative runtime state is listed in the top sections of this file; lower sections retain historical rollout notes where relevant.

# FINAL RUNTIME CONTRACTS
TokenRegistry deployed at: `0x140fbAA1e8BE387082aeb6088E4Ffe1bf3Ba4d4f`
PaymentKitaVault deployed at: `0x67d0af7f163F45578679eDa4BDf9042E3E5FEc60`
PaymentKitaRouter deployed at: `0x1b91B56aD3aA6B35e5EAe18EE19A42574A545802`
PaymentKitaGateway deployed at: `0xc1d4Ed499417B560A5Df53bA5e2b1A54755Ce58C`
Previous active gateway: `0x08409b0fa63b0bCEb4c4B49DBf286ff943b60011`
Older gateway: `0x3547cBE71Fe65e5325f27F411d1e85641BD196aC`
Legacy gateway: `0xf0daa1a24556B68B4636FBE1c90dE326842A164C`
TokenSwapper deployed at: `0x8B6c7770D4B8AaD2d600e0cf5df3Eea5Bc0EB0fe`

Gateway modules wired:
- validator: `0xb7A893672189B46632109CC15De8986e2B8be1c6`
- quote: `0xfc70c24D9dC932572A067349E4D3A2eeb0280b31`
- execution: `0x5852Bec7f3Ce38Ffdd8d1c9F48c88a620a9e6078`
- privacy: `0xd8a6818468eBB65527118308B48c1A969977A086`
FeePolicyManager: `0x1443C7D4dbB86035739A69fBB39Ebb76Ba7590fc`
Default fee strategy: `0x53689F9119345480C7b16B085b27F93A826b65CA`
StealthEscrowFactory: `0x882A5d22d27C2e60dA7356DCdEA49bE3bCFbcBA3`

Runtime verification and auth summary:
- `PaymentKitaGateway 0xc1d4...`: Pass - Verified
- `StargateSenderAdapter 0x44D1...`: Already verified
- `StargateReceiverAdapter 0xE09e...`: Already verified
- `CCIPReceiverAdapter 0x565C...`: Already verified
- `HyperbridgeTokenGatewaySender 0x563F...`: Already verified
- `gateway.isAuthorizedAdapter(...)`:
  - `CCIPReceiver 0x565CcC753Ea1e54f9F2FEFF1acC8dC4036fFC26e = true`
  - `HTGReceiver 0x4511848F91Fd0f5F164FfBEf2e1c8BDE24a107a3 = true`
  - `StargateReceiver 0xE09ed3D37ac311F9ef4aCF8927C27495Cc0D291A = true`
- `vault.authorizedSpenders(...)`:
  - `Gateway 0xc1d4Ed499417B560A5Df53bA5e2b1A54755Ce58C = true`
  - `HTGSender 0x563F10de351393b183FF1d8eF797bbbF3ab5e5e2 = true`
  - `StargateSender 0x44D10404d8e078af761e71c03d97cec30EE0a2A3 = true`
- `defaultBridgeTypes`:
  - `eip155:42161 -> 2`
  - `eip155:137 -> 2`

Cross-token Stargate canary final on `2026-03-20`:
- `A` Base -> Arbitrum regular `IDRX -> USDT`
  - source tx `0xe12fbc09125f0474784b6665c1c16e8da8e72d6efeaa6da60583569f63886b6a`
  - settled on destination: `0x37`
- `B` Base -> Polygon regular `IDRX -> USDT`
  - source tx `0x1cfef99c2c3d0198610f3cfe35fedd161dad21ec5317c92231282b89f1b29ed7`
  - settled on destination: `0x37`
- `E` Polygon -> Base regular `USDT -> IDRX`
  - source tx `0xd9b5fb9213dcf4640ea07580bf43f5a349ef0746f6c5e896b9dab643712a0bf9`
  - settled on Base: `0x69c`
- `K` Polygon -> Base privacy `USDT -> IDRX`
  - source tx `0x2b91fff6f7c4fd8add57e3c577986d00aab6317fbca4fd584c303929ddfe4e4b`
  - settled on Base: `0x69b`
  - `privacyForwardCompleted = true`
- Base receiver USDC balance after rerun: `0`
- Base stealth IDRX balance after rerun: `0`

## Historical Summary
- `2026-03-09`: gateway V2 redeploy completed
  - gateway `0x3547cBE71Fe65e5325f27F411d1e85641BD196aC`
  - tx `0xd4fd369b9369abff704abef82208762041e0f9d26aedaa2bd57e4484493e8dae`
- `2026-03-10`: gateway privacy patch redeploy completed
  - gateway `0x08409b0fa63b0bCEb4c4B49DBf286ff943b60011`
  - tx `0xcc84de6f55d6bd768f716b2b7a88e99c8c65ae2a3ca4477c606a6b8c149773e1`
  - privacy module `0xd8a6818468eBB65527118308B48c1A969977A086`
  - escrow factory `0x882A5d22d27C2e60dA7356DCdEA49bE3bCFbcBA3`

CCIPSender deployed at: `0x47FEA6C20aC5F029BAB99Ec2ed756d94c54707DE`
CCIPReceiverAdapter active runtime at: `0x565CcC753Ea1e54f9F2FEFF1acC8dC4036fFC26e`
HyperbridgeSender deployed at: `0x563F10de351393b183FF1d8eF797bbbF3ab5e5e2`
HyperbridgeReceiver active runtime at: `0x4511848F91Fd0f5F164FfBEf2e1c8BDE24a107a3`
Deauthorized HTG Receiver: `0x5649f75c6aD1140bbABed12978Ec27AdADE4E2d4`
StargateSenderAdapter active runtime at: `0x44D10404d8e078af761e71c03d97cec30EE0a2A3`
StargateReceiverAdapter active runtime at: `0xE09ed3D37ac311F9ef4aCF8927C27495Cc0D291A`
StargateReceiverAdapter previous runtime at: `0x26C277f9ce9649637BfC325Bce3fA83a60921A5A`

# CCIP ROUTE STATUS (Base <-> Arbitrum)
CCIP sender kept live: `0x47FEA6C20aC5F029BAB99Ec2ed756d94c54707DE`
Current live receiver on Base: `0x565CcC753Ea1e54f9F2FEFF1acC8dC4036fFC26e`
Patch status:
- Canonical token mismatch fix landed in `src/integrations/ccip/CCIPReceiver.sol`
- Validated locally in adapter tests: `31/31 PASS`
- Live receiver rewire broadcast: complete on `2026-03-15`
- Kept Arbitrum-side sender now points to Base receiver `0x565CcC753Ea1e54f9F2FEFF1acC8dC4036fFC26e`
Operational note:
- `CCIP` is not yet approved as official fallback for `Base <-> Arbitrum`
- previous canary failures were generated against the old receiver and must be re-tested against the new live receiver

# HYPERBRIDGE TOKEN GATEWAY ROUTE STATUS (Base <-> Arbitrum)
HTG sender (Base -> Arbitrum) after timeout rollout `2026-03-14`: `0x563F10de351393b183FF1d8eF797bbbF3ab5e5e2`
HTG receiver (Arbitrum -> Base settlement executor peer): `0x4511848F91Fd0f5F164FfBEf2e1c8BDE24a107a3`
Deauthorized old HTG receiver: `0x5649f75c6aD1140bbABed12978Ec27AdADE4E2d4`
Remote HTG receiver (Arbitrum): `0xF46C1fCff7E42bACF3B769C2364ffb86Ca52FCF6`
Token gateway host: `0xFd413e3AFe560182C4471F4d143A96d3e259B6dE`
Active route timeout:
- `eip155:42161 -> 10800`
- `eip155:8453 -> 14400` on remote sender
Verification:
- HTG sender unit tests: `12/12 PASS`
- HTG receiver unit tests: `8/8 PASS`
- On-chain route readiness revalidated previously: `PASS=22 FAIL=0`

# STARGATE MIGRATION STATUS
Stargate sender deployed on Base: `0x44D10404d8e078af761e71c03d97cec30EE0a2A3`
Stargate receiver active on Base: `0xE09ed3D37ac311F9ef4aCF8927C27495Cc0D291A` (RescuableAdapter V2)
Stargate receiver previous runtime on Base: `0x26C277f9ce9649637BfC325Bce3fA83a60921A5A`
USDC pool: `0x27a16dc786820B16E5c9028b75B99F6f604b5d26`
Migration state:
- Full-mesh dry-run `Base <-> Arbitrum`, `Base <-> Polygon`, `Arbitrum <-> Polygon`: pass
- Live full-mesh cutover broadcast: complete on `2026-03-15`
- Legacy LayerZero deauthorization broadcast: complete on `2026-03-15`
- Gateway default bridge now reads:
  - `eip155:42161 -> 2`
  - `eip155:137 -> 2`
- Live readback:
  - `gateway.isAuthorizedAdapter(0xc4c28aeeE5bb312970a7266461838565E1eEEc1a) = false`
  - `vault.authorizedSpenders(0xc4c28aeeE5bb312970a7266461838565E1eEEc1a) = false`
  - `vault.authorizedSpenders(0x11bfD843dCEbF421d2f2A07D2C8BA5Db85E501E9) = false`
- Legacy direct `LayerZero` contracts remain deployed only as historical artifacts; runtime authorization is removed
- Live route readback on `2026-03-19` after V2 cutover:
  - `Base -> Polygon` destination adapter: `0x0000000000000000000000001808bd03899c80d3c9619ad9740e8db04f32b471`
  - `Base -> Arbitrum` destination adapter: `0x000000000000000000000000a0502c041aae8ae1a4141d7e7937b34a01510fcf`
  - Base receiver active source routes now terminate on `0xE09ed3D37ac311F9ef4aCF8927C27495Cc0D291A`
  - Base gateway adapter auth:
    - old `0x26C277f9ce9649637BfC325Bce3fA83a60921A5A = false`
    - new `0xE09ed3D37ac311F9ef4aCF8927C27495Cc0D291A = true`
- Live sender-only privacy patch broadcast: complete on `2026-03-19`
  - Base sender runtime replaced with `0x44D10404d8e078af761e71c03d97cec30EE0a2A3`
  - Base router `bridgeType=2` readback:
    - `eip155:42161 -> 0x44D10404d8e078af761e71c03d97cec30EE0a2A3`
    - `eip155:137 -> 0x44D10404d8e078af761e71c03d97cec30EE0a2A3`
- Privacy rescue + verification on `2026-03-19`
  - Base stealth escrow rescued:
    - `setForwarder`: `0x1c80508bc1dcede9c7c61d61e3cad4ee45d83a77576cdcc258c1691d1c7fa77e`
    - `forwardToken`: `0x1c7b875c70f796b5134653cc434588b054b23a787edda3a0b3b4d52b9f20a8ba`
  - Base-side stealth escrow balance after rescue and new privacy canary: `0`
  - Privacy canary source tx:
    - `Base -> Polygon`: `0x62c7158085959fbfa808ad17263eafe8f844b002ef84e1f8731a5bfc85fc87e8`

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
Gateway default bridge for eip155:137: 0 (set by `RedeployPaymentKitaGatewayV2PrivacyPatch`)
Validation: re-run `make ccip-validate-dry`

# LEGACY LAYERZERO ROUTE STATUS (Base -> Polygon)
Route CAIP2: eip155:137
Bridge type: 2 (LayerZero)
Sender dstEid: 30109
Sender dstPeer: pending re-validate after latest Base redeploy
Receiver srcEid: 30109
Receiver srcPeer: pending re-validate after latest Base redeploy
Validation: re-run `make lz-validate-dry`
Retirement note:
- direct `LayerZero` on Polygon lane has been cut over to `Stargate`; legacy runtime authorization is removed

# AUTHORIZED TOKEN
Registered bridge token as supported: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
Registered BASE_USDC: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
Registered BASE_USDE: 0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34
Registered BASE_WETH: 0x4200000000000000000000000000000000000006
Registered BASE_CBETH: 0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22
Registered BASE_CBBTC: 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf
Registered BASE_WBTC: 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c
Registered BASE_IDRX: 0x18Bc5bcC660cf2B9cE3cd51a404aFe1a0cBD3C22
Registered BASE_XSGD: 0x0A4C9cb2778aB3302996A34BeFCF9a8Bc288C33b
Registered BASE_MYRC: 0x3eD03E95DD894235090B3d4A49E0C3239EDcE59e

## Historical Ops Notes
- old privacy gate commands and phase-4 readiness tables were removed from the main body
- use `RUNTIME_ACTIVE_ADDRESSES.md` for current runtime references

## Privacy V2 Patch Redeploy Command
Gunakan ini jika butuh redeploy gateway baru dengan module fresh + fee policy manager + stealth escrow factory (tanpa manual wiring berulang):

```bash
cd payment-kita.evm.smartcontract
source .env

export REDEPLOY_V2_PATCH_VAULT=0x67d0af7f163F45578679eDa4BDf9042E3E5FEc60
export REDEPLOY_V2_PATCH_ROUTER=0x1b91B56aD3aA6B35e5EAe18EE19A42574A545802
export REDEPLOY_V2_PATCH_TOKEN_REGISTRY=0x140fbAA1e8BE387082aeb6088E4Ffe1bf3Ba4d4f
export REDEPLOY_V2_PATCH_FEE_RECIPIENT=0x2Bda11F04b8F96D361D2DBB1bA8c36B744B4b42A
export REDEPLOY_V2_PATCH_OLD_GATEWAY=0x08409b0fa63b0bCEb4c4B49DBf286ff943b60011
export REDEPLOY_V2_PATCH_COPY_CONFIG_FROM_OLD_GATEWAY=true
export REDEPLOY_V2_PATCH_DEPLOY_MODULES=true
export REDEPLOY_V2_PATCH_DEPLOY_FEE_POLICY=true
export REDEPLOY_V2_PATCH_DEPLOY_ESCROW_FACTORY=true
export REDEPLOY_V2_PATCH_DEFAULT_DEST_CAIP2=eip155:137
export REDEPLOY_V2_PATCH_DEFAULT_BRIDGE_TYPE=0

# dry-run
make redeploy-gateway-v2-privacy-patch-dry

# broadcast + verify
make redeploy-gateway-v2-privacy-patch
```
