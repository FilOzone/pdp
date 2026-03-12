#!/bin/bash
set -euo pipefail

# upgrade.sh: Completes an upgrade for PDPVerifier.
# Required args: RPC_URL, PDP_VERIFIER_PROXY_ADDRESS, NEW_PDP_VERIFIER_IMPLEMENTATION_ADDRESS
# Direct-broadcast mode also requires: KEYSTORE, PASSWORD
# SAFE/contract-owner mode is auto-detected and prints calldata instead of broadcasting.

ZERO_ADDRESS="0x0000000000000000000000000000000000000000"
IMPLEMENTATION_SLOT="0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"

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
  echo "This upgrade must be executed by the owner contract (for example a SAFE multisig)."
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

if [ -z "${CHAIN:-}" ]; then
  CHAIN=$(cast chain-id --rpc-url "$RPC_URL")
  if [ -z "$CHAIN" ]; then
    echo "Error: Failed to detect chain ID from RPC"
    exit 1
  fi
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

# Get the upgrade plan (if any). Old deployments such as v3.1.0 do not expose nextUpgrade().
UPGRADE_PLAN_OUTPUT=""
if UPGRADE_PLAN_OUTPUT=$(cast call --rpc-url "$RPC_URL" -f "$ZERO_ADDRESS" "$PDP_VERIFIER_PROXY_ADDRESS" "nextUpgrade()(address,uint96)" 2>/dev/null); then
  UPGRADE_PLAN=($UPGRADE_PLAN_OUTPUT)
  PLANNED_PDP_VERIFIER_IMPLEMENTATION_ADDRESS=${UPGRADE_PLAN[0]}
  AFTER_EPOCH=${UPGRADE_PLAN[1]}

  if [ -n "$PLANNED_PDP_VERIFIER_IMPLEMENTATION_ADDRESS" ] && [ "$PLANNED_PDP_VERIFIER_IMPLEMENTATION_ADDRESS" != "$ZERO_ADDRESS" ]; then
    echo "Detected planned upgrade (two-step mechanism)"

    if [ "$(lowercase "$PLANNED_PDP_VERIFIER_IMPLEMENTATION_ADDRESS")" != "$(lowercase "$NEW_PDP_VERIFIER_IMPLEMENTATION_ADDRESS")" ]; then
      echo "NEW_PDP_VERIFIER_IMPLEMENTATION_ADDRESS ($NEW_PDP_VERIFIER_IMPLEMENTATION_ADDRESS) != planned ($PLANNED_PDP_VERIFIER_IMPLEMENTATION_ADDRESS)"
      exit 1
    fi
    echo "Upgrade plan matches ($NEW_PDP_VERIFIER_IMPLEMENTATION_ADDRESS)"

    CURRENT_EPOCH=$(cast block-number --rpc-url "$RPC_URL" 2>/dev/null)

    if [ "$CURRENT_EPOCH" -lt "$AFTER_EPOCH" ]; then
      echo "Not time yet ($CURRENT_EPOCH < $AFTER_EPOCH)"
      exit 1
    fi
    echo "Upgrade ready ($CURRENT_EPOCH >= $AFTER_EPOCH)"
  else
    echo "No planned upgrade detected (nextUpgrade returns zero)"
    echo "Error: This contract requires a planned upgrade. Please call announce-planned-upgrade.sh first."
    exit 1
  fi
else
  echo "nextUpgrade() method not found, using one-step mechanism (legacy direct upgrade)"
fi

MIGRATE_DATA=$(cast calldata "migrate()")
UPGRADE_DATA=$(cast calldata "upgradeToAndCall(address,bytes)" "$NEW_PDP_VERIFIER_IMPLEMENTATION_ADDRESS" "$MIGRATE_DATA")

if address_has_code "$PROXY_OWNER"; then
  print_contract_owner_tx "$UPGRADE_DATA"
  exit 0
fi

require_env "KEYSTORE"
require_env "PASSWORD"

ADDR=$(cast wallet address --keystore "$KEYSTORE" --password "$PASSWORD")
echo "Using owner address: $ADDR"

if [ "$(lowercase "$PROXY_OWNER")" != "$(lowercase "$ADDR")" ]; then
  echo "Supplied KEYSTORE ($ADDR) is not the proxy owner ($PROXY_OWNER)."
  exit 1
fi

NONCE=$(cast nonce --rpc-url "$RPC_URL" "$ADDR")

echo "Upgrading proxy and calling migrate..."
TX_HASH=$(cast send --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" "$PDP_VERIFIER_PROXY_ADDRESS" "upgradeToAndCall(address,bytes)" "$NEW_PDP_VERIFIER_IMPLEMENTATION_ADDRESS" "$MIGRATE_DATA" \
  --nonce "$NONCE" \
  --json | jq -r '.transactionHash')

if [ -z "$TX_HASH" ]; then
  echo "Error: Failed to send upgrade transaction"
  echo "The transaction may have failed due to:"
  echo "- Insufficient permissions (not owner)"
  echo "- Proxy is paused or locked"
  echo "- Implementation address is invalid"
  exit 1
fi

echo "Upgrade transaction sent: $TX_HASH"
echo "Waiting for confirmation..."

cast receipt --rpc-url "$RPC_URL" "$TX_HASH" --confirmations 1 > /dev/null

echo "Verifying upgrade..."
NEW_IMPL=$(cast rpc --rpc-url "$RPC_URL" eth_getStorageAt "$PDP_VERIFIER_PROXY_ADDRESS" "$IMPLEMENTATION_SLOT" latest | sed 's/"//g' | sed 's/0x000000000000000000000000/0x/')
EXPECTED_IMPL=$(lowercase "$NEW_PDP_VERIFIER_IMPLEMENTATION_ADDRESS")

if [ "$NEW_IMPL" = "$EXPECTED_IMPL" ]; then
    echo "Upgrade successful! Proxy now points to: $NEW_PDP_VERIFIER_IMPLEMENTATION_ADDRESS"
else
    echo "Warning: Could not verify upgrade. Please check manually."
    echo "Expected: $NEW_PDP_VERIFIER_IMPLEMENTATION_ADDRESS"
    echo "Got: $NEW_IMPL"
fi
