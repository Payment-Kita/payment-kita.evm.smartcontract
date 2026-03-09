# DEPLOYMENT CONTRACT
Status: belum diisi pada dokumen ini.

## PRIVACY READINESS MATRIX (PHASE 4)
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

PRIVACY_GATE_GATEWAY=<BSC_GATEWAY> \
PRIVACY_GATE_VAULT=<BSC_VAULT> \
PRIVACY_GATE_SWAPPER=<BSC_SWAPPER> \
PRIVACY_GATE_PRIVACY_MODULE=<BSC_PRIVACY_MODULE> \
BASE_RPC_URL=$BSC_RPC_URL \
make validate-privacy-route-gate PRIVACY_GATE_SKIP_TESTS=1
```
