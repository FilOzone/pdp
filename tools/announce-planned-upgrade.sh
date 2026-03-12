#!/bin/bash
set -euo pipefail

# announce-planned-upgrade.sh: Announces a planned upgrade for PDPVerifier.
# Required args: RPC_URL, PDP_VERIFIER_PROXY_ADDRESS, NEW_PDP_VERIFIER_IMPLEMENTATION_ADDRESS, AFTER_EPOCH
# Direct-broadcast mode also requires: KEYSTORE, PASSWORD
# SAFE/contract-owner mode is auto-detected and prints calldata instead of broadcasting.

ZERO_ADDRESS="0x0000000000000000000000000000000000000000"

require_env() {
  local var_name=$1
  if [ -z "${!var_name:-}" ]; then
    echo "Error: ${var_name} is not set"
    exit 1
  fi
}

lowercase() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

address_has_code() {
  local address=$1
  local code
  code=$(cast code --rpc-url "$RPC_URL" "$address" 2>/dev/null || true)
  [ -n "$code" ] && [ "$code" != "0x" ]
}

print_contract_owner_tx() {
  local calldata=$1
  local owner_nonce=""

  owner_nonce=$(cast call --rpc-url "$RPC_URL" "$PROXY_OWNER" "nonce()(uint256)" 2>/dev/null || true)

  echo "Detected contract owner: $PROXY_OWNER"
  echo "This deployment must be announced by the owner contract (for example a SAFE multisig)."
  echo
  echo "Submit this transaction via the owner contract workflow:"
  echo "  target: $PDP_VERIFIER_PROXY_ADDRESS"
  echo "  value: 0"
  echo "  data: $calldata"
  if [ -n "$owner_nonce" ]; then
    echo "  owner nonce: $owner_nonce"
  fi
}

require_env "RPC_URL"
require_env "PDP_VERIFIER_PROXY_ADDRESS"
require_env "NEW_PDP_VERIFIER_IMPLEMENTATION_ADDRESS"
require_env "AFTER_EPOCH"

if [ -z "${CHAIN:-}" ]; then
  CHAIN=$(cast chain-id --rpc-url "$RPC_URL")
  if [ -z "$CHAIN" ]; then
    echo "Error: Failed to detect chain ID from RPC"
    exit 1
  fi
fi

CURRENT_EPOCH=$(cast block-number --rpc-url "$RPC_URL" 2>/dev/null)

if [ "$CURRENT_EPOCH" -ge "$AFTER_EPOCH" ]; then
  echo "AFTER_EPOCH must be in the future ($CURRENT_EPOCH >= $AFTER_EPOCH)"
  exit 1
fi

echo "Announcing planned upgrade after $(($AFTER_EPOCH - $CURRENT_EPOCH)) epochs"

if ! cast call --rpc-url "$RPC_URL" -f "$ZERO_ADDRESS" "$PDP_VERIFIER_PROXY_ADDRESS" "nextUpgrade()(address,uint96)" >/dev/null 2>&1; then
  echo "This deployment does not support planned upgrade announcements."
  echo "It is likely running a pre-announcement version such as v3.1.0."
  echo "Use tools/upgrade.sh directly for the upgrade transaction."
  exit 1
fi

PROXY_OWNER=$(cast call --rpc-url "$RPC_URL" -f "$ZERO_ADDRESS" "$PDP_VERIFIER_PROXY_ADDRESS" "owner()(address)" 2>/dev/null)
if [ -z "$PROXY_OWNER" ]; then
  echo "Error: Failed to read proxy owner"
  exit 1
fi

if [ -n "${SAFE_ADDRESS:-}" ] && [ "$(lowercase "$SAFE_ADDRESS")" != "$(lowercase "$PROXY_OWNER")" ]; then
  echo "SAFE_ADDRESS ($SAFE_ADDRESS) does not match proxy owner ($PROXY_OWNER)."
  exit 1
fi

ANNOUNCE_DATA=$(cast calldata "announcePlannedUpgrade((address,uint96))" "($NEW_PDP_VERIFIER_IMPLEMENTATION_ADDRESS,$AFTER_EPOCH)")

if address_has_code "$PROXY_OWNER"; then
  print_contract_owner_tx "$ANNOUNCE_DATA"
  exit 0
fi

require_env "KEYSTORE"
require_env "PASSWORD"

ADDR=$(cast wallet address --keystore "$KEYSTORE" --password "$PASSWORD")
echo "Sending announcement from owner address: $ADDR"

if [ "$(lowercase "$PROXY_OWNER")" != "$(lowercase "$ADDR")" ]; then
  echo "Supplied KEYSTORE ($ADDR) is not the proxy owner ($PROXY_OWNER)."
  exit 1
fi

NONCE=$(cast nonce --rpc-url "$RPC_URL" "$ADDR")

TX_HASH=$(cast send --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" "$PDP_VERIFIER_PROXY_ADDRESS" "announcePlannedUpgrade((address,uint96))" "($NEW_PDP_VERIFIER_IMPLEMENTATION_ADDRESS,$AFTER_EPOCH)" \
  --nonce "$NONCE" \
  --json | jq -r '.transactionHash')

if [ -z "$TX_HASH" ]; then
  echo "Error: Failed to send announcePlannedUpgrade transaction"
  exit 1
fi

echo "announcePlannedUpgrade transaction sent: $TX_HASH"
