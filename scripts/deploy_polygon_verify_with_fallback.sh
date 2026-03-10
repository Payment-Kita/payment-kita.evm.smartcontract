#!/usr/bin/env bash
set -u
set -o pipefail

if [[ -z "${PRIVATE_KEY:-}" ]]; then
  echo "Missing PRIVATE_KEY"
  exit 1
fi

if [[ -z "${POLYGONSCAN_API_KEY:-}" ]]; then
  echo "Missing POLYGONSCAN_API_KEY"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RPCS=(
  "https://polygon-mainnet.infura.io/v3/136ed41a59fd4cb2990353e603345171"
  "https://polygon-mainnet.g.alchemy.com/v2/K9PzwLloeXxcOuFEx_fgR"
  "https://polygon-mainnet.g.alchemy.com/v2/k9jTbZWq2LZngKpuaQTBZ "
)

for rpc in "${RPCS[@]}"; do
  echo "Attempting deploy resume using RPC: $rpc"
  if forge script script/DeployPolygon.s.sol:DeployPolygon \
    --rpc-url "$rpc" \
    --private-key "$PRIVATE_KEY" \
    --broadcast \
    --verify \
    --etherscan-api-key "$POLYGONSCAN_API_KEY" \
    --chain polygon \
    --resume \
    --slow \
    -vvvv \
    "$@"; then
    echo "Deploy resume completed using RPC: $rpc"
    exit 0
  fi
  echo "RPC failed: $rpc"
done

echo "All fallback RPC endpoints failed."
exit 1
