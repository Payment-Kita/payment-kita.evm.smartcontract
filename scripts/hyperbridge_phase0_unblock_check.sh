#!/usr/bin/env bash
set -euo pipefail

# Phase 0 unblock validator for Hyperbridge Token Gateway readiness.
# Checks:
# 1) Contract code existence (host + token gateway)
# 2) Stable asset mapping on token gateway (erc20/erc6160)
# 3) Base token gateway instance mapping toward Polygon state machine

BASE_RPC_URL="${BASE_RPC_URL:-}"
POLYGON_RPC_URL="${POLYGON_RPC_URL:-}"

BASE_HOST="${BASE_HYPERBRIDGE_HOST:-0x6FFe92e4d7a9D589549644544780e6725E84b248}"
POLYGON_HOST="${POLYGON_HYPERBRIDGE_HOST:-0xD8d3db17C1dF65b301D45C84405CcAC1395C559a}"

BASE_TOKEN_GATEWAY="${BASE_TOKEN_GATEWAY:-0xFd413e3AFe560182C4471F4d143A96d3e259B6dE}"
# Official mainnet docs currently list Polygon TokenGateway as:
# https://docs.hyperbridge.network/developers/evm/contract-addresses/mainnet/
POLYGON_TOKEN_GATEWAY="${POLYGON_TOKEN_GATEWAY:-0x8b536105b6Fae2aE9199f5146D3C57Dfe53b614E}"

STATE_MACHINE_BASE="${STATE_MACHINE_BASE:-EVM-8453}"
STATE_MACHINE_POLYGON="${STATE_MACHINE_POLYGON:-EVM-137}"

ASSET_SYMBOLS="${ASSET_SYMBOLS:-USDC USDT DAI}"

if [[ -z "$BASE_RPC_URL" || -z "$POLYGON_RPC_URL" ]]; then
  echo "Missing BASE_RPC_URL or POLYGON_RPC_URL"
  exit 1
fi

json_rpc() {
  local rpc_url="$1"
  local method="$2"
  local params="$3"
  curl -sS "$rpc_url" \
    -H 'content-type: application/json' \
    --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$method\",\"params\":$params}"
}

extract_result() {
  sed -n 's/.*"result":"\([^"]*\)".*/\1/p'
}

extract_error() {
  sed -n 's/.*"error":{\(.*\)}.*/\1/p'
}

to_lc() {
  tr '[:upper:]' '[:lower:]'
}

is_zero_32() {
  local v
  v="$(echo "$1" | to_lc)"
  [[ "$v" == "0x" ]] && return 0
  [[ "$v" == "0x0000000000000000000000000000000000000000000000000000000000000000" ]] && return 0
  return 1
}

code_exists() {
  local rpc_url="$1"
  local addr="$2"
  local out res err
  out="$(json_rpc "$rpc_url" "eth_getCode" "[\"$addr\",\"latest\"]")" || return 1
  res="$(echo "$out" | extract_result)"
  err="$(echo "$out" | extract_error)"
  if [[ -n "$err" || -z "$res" ]]; then
    return 1
  fi
  [[ "$res" != "0x" ]]
}

call_addr_return() {
  local rpc_url="$1"
  local to="$2"
  local data="$3"
  local out res err
  out="$(json_rpc "$rpc_url" "eth_call" "[{\"to\":\"$to\",\"data\":\"$data\"},\"latest\"]")" || return 1
  res="$(echo "$out" | extract_result)"
  err="$(echo "$out" | extract_error)"
  if [[ -n "$err" || -z "$res" ]]; then
    return 1
  fi
if is_zero_32 "$res"; then
    echo "0x0000000000000000000000000000000000000000"
    return 0
  fi
  local raw
  raw="${res#0x}"
  if [[ ${#raw} -lt 40 ]]; then
    echo "0x0000000000000000000000000000000000000000"
    return 0
  fi
  echo "0x${raw: -40}"
}

call_instance() {
  local rpc_url="$1"
  local gateway="$2"
  local state_machine="$3"
  local sm_hex args calldata
  sm_hex="$(cast --from-utf8 "$state_machine")"
  args="$(cast abi-encode "instance(bytes)" "$sm_hex")"
  calldata="0x0bddd96c${args#0x}" # instance(bytes)
  call_addr_return "$rpc_url" "$gateway" "$calldata"
}

pass_count=0
fail_count=0

pass() {
  echo "PASS: $1"
  pass_count=$((pass_count + 1))
}

fail() {
  echo "FAIL: $1"
  fail_count=$((fail_count + 1))
}

echo "== Phase 0 Unblock Check =="
echo "Base host:           $BASE_HOST"
echo "Polygon host:        $POLYGON_HOST"
echo "Base token gateway:  $BASE_TOKEN_GATEWAY"
echo "Polygon token gate.: ${POLYGON_TOKEN_GATEWAY:-<NOT_SET>}"
echo "Assets:              $ASSET_SYMBOLS"
echo

if code_exists "$BASE_RPC_URL" "$BASE_HOST"; then
  pass "Base host has code"
else
  fail "Base host has no code / RPC issue"
fi

lc() {
  echo "$1" | to_lc
}

if code_exists "$POLYGON_RPC_URL" "$POLYGON_HOST"; then
  pass "Polygon host has code"
else
  fail "Polygon host has no code / RPC issue"
fi

if code_exists "$BASE_RPC_URL" "$BASE_TOKEN_GATEWAY"; then
  pass "Base token gateway has code"
else
  fail "Base token gateway has no code / RPC issue"
fi

check_asset_mapping() {
  local chain_name="$1"
  local rpc_url="$2"
  local gateway_addr="$3"
  local symbol="$4"
  local asset_id erc20_addr erc6160_addr

  asset_id="$(cast keccak "$symbol" | tr '[:upper:]' '[:lower:]')"
  erc20_addr="$(call_addr_return "$rpc_url" "$gateway_addr" "0x6967197a${asset_id#0x}" || echo "0x0000000000000000000000000000000000000000")"
  erc6160_addr="$(call_addr_return "$rpc_url" "$gateway_addr" "0x6277e516${asset_id#0x}" || echo "0x0000000000000000000000000000000000000000")"

  echo "$chain_name asset $symbol id: $asset_id"
  echo "$chain_name erc20($symbol):   $erc20_addr"
  echo "$chain_name erc6160($symbol): $erc6160_addr"

  if [[ "$(lc "$erc20_addr")" != "0x0000000000000000000000000000000000000000" || "$(lc "$erc6160_addr")" != "0x0000000000000000000000000000000000000000" ]]; then
    pass "$chain_name gateway has $symbol asset mapping (erc20 or erc6160)"
  else
    fail "$chain_name gateway missing $symbol asset mapping"
  fi
}

for sym in $ASSET_SYMBOLS; do
  check_asset_mapping "Base" "$BASE_RPC_URL" "$BASE_TOKEN_GATEWAY" "$sym"
done

BASE_INSTANCE_POLYGON="$(call_instance "$BASE_RPC_URL" "$BASE_TOKEN_GATEWAY" "$STATE_MACHINE_POLYGON" || echo "0x0000000000000000000000000000000000000000")"
echo "Base instance(${STATE_MACHINE_POLYGON}): $BASE_INSTANCE_POLYGON"
if [[ "$(lc "$BASE_INSTANCE_POLYGON")" == "$(lc "$BASE_TOKEN_GATEWAY")" ]]; then
  fail "Base instance(${STATE_MACHINE_POLYGON}) returns self (likely no explicit remote gateway mapping)"
elif [[ "$(lc "$BASE_INSTANCE_POLYGON")" == "0x0000000000000000000000000000000000000000" ]]; then
  fail "Base instance(${STATE_MACHINE_POLYGON}) is zero"
else
  pass "Base instance(${STATE_MACHINE_POLYGON}) resolved to remote gateway address"
fi

if [[ -z "$POLYGON_TOKEN_GATEWAY" ]]; then
  fail "POLYGON_TOKEN_GATEWAY is not set (official address unresolved)"
else
  if code_exists "$POLYGON_RPC_URL" "$POLYGON_TOKEN_GATEWAY"; then
    pass "Polygon token gateway has code"
    for sym in $ASSET_SYMBOLS; do
      check_asset_mapping "Polygon" "$POLYGON_RPC_URL" "$POLYGON_TOKEN_GATEWAY" "$sym"
    done
  else
    fail "Polygon token gateway has no code / RPC issue"
  fi
fi

echo
echo "Summary: PASS=$pass_count FAIL=$fail_count"

if [[ $fail_count -gt 0 ]]; then
  echo "Phase 0 verdict: NO-GO"
  exit 2
fi

echo "Phase 0 verdict: GO"
