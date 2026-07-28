#!/bin/bash
set -euo pipefail

# announce-planned-upgrade.sh: Announces a planned upgrade for PDPVerifier.
# Required args: RPC_URL or ETH_RPC_URL, PDP_VERIFIER_PROXY_ADDRESS, NEW_PDP_VERIFIER_IMPLEMENTATION_ADDRESS
# Set exactly one of:
#   UPGRADE_DELAY_EPOCHS  Epochs from now before the upgrade may occur (preferred; calls announceUpgradePlan)
#   AFTER_EPOCH           Absolute epoch before which the upgrade may not occur (deprecated; calls announcePlannedUpgrade,
#                         for deployments predating announceUpgradePlan)
# Direct-broadcast mode also requires: KEYSTORE, PASSWORD
# SAFE/contract-owner mode is auto-detected and prints calldata instead of broadcasting.

RPC_URL="${RPC_URL:-${ETH_RPC_URL:-}}"
if [ -z "${RPC_URL:-}" ]; then
  echo "Error: RPC_URL or ETH_RPC_URL is not set"
  exit 1
fi
export ETH_RPC_URL="${ETH_RPC_URL:-$RPC_URL}"

ZERO_ADDRESS="0x0000000000000000000000000000000000000000"

require_env() {
  local var_name=$1
  if [ -z "${!var_name:-}" ]; then
    echo "Error: ${var_name} is not set"
    exit 1
  fi
}

normalize_address() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

same_address() {
  [ "$(normalize_address "$1")" = "$(normalize_address "$2")" ]
}

address_has_code() {
  local address=$1
  local code
  code=$(cast code "$address" 2>/dev/null || true)
  [ -n "$code" ] && [ "$code" != "0x" ]
}

print_contract_owner_tx() {
  local calldata=$1
  local owner_nonce=""

  owner_nonce=$(cast call "$PROXY_OWNER" "nonce()(uint256)" 2>/dev/null || true)

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

require_env "PDP_VERIFIER_PROXY_ADDRESS"
require_env "NEW_PDP_VERIFIER_IMPLEMENTATION_ADDRESS"

if [ -n "${UPGRADE_DELAY_EPOCHS:-}" ] && [ -n "${AFTER_EPOCH:-}" ]; then
  echo "Error: Set only one of UPGRADE_DELAY_EPOCHS or AFTER_EPOCH, not both"
  exit 1
fi
if [ -z "${UPGRADE_DELAY_EPOCHS:-}" ] && [ -z "${AFTER_EPOCH:-}" ]; then
  echo "Error: Set UPGRADE_DELAY_EPOCHS (preferred) or AFTER_EPOCH (deprecated)"
  exit 1
fi

if [ -z "${CHAIN:-}" ]; then
  CHAIN=$(cast chain-id)
  if [ -z "$CHAIN" ]; then
    echo "Error: Failed to detect chain ID from RPC"
    exit 1
  fi
fi

CURRENT_EPOCH=$(cast block-number 2>/dev/null)

if [ -n "${UPGRADE_DELAY_EPOCHS:-}" ]; then
  echo "Announcing planned upgrade after $UPGRADE_DELAY_EPOCHS epochs (the delay starts when this announcement executes)"
else
  if [ "$CURRENT_EPOCH" -ge "$AFTER_EPOCH" ]; then
    echo "AFTER_EPOCH must be in the future ($CURRENT_EPOCH >= $AFTER_EPOCH)"
    exit 1
  fi
  echo "Announcing planned upgrade after $(($AFTER_EPOCH - $CURRENT_EPOCH)) epochs (deprecated method)"
fi

if ! cast call -f "$ZERO_ADDRESS" "$PDP_VERIFIER_PROXY_ADDRESS" "nextUpgrade()(address,uint96)" >/dev/null 2>&1; then
  echo "This deployment does not support planned upgrade announcements."
  echo "It is likely running a pre-announcement version such as v3.1.0."
  echo "Use tools/upgrade.sh directly for the upgrade transaction."
  exit 1
fi

PROXY_OWNER=$(cast call -f "$ZERO_ADDRESS" "$PDP_VERIFIER_PROXY_ADDRESS" "owner()(address)" 2>/dev/null)
if [ -z "$PROXY_OWNER" ]; then
  echo "Error: Failed to read proxy owner"
  exit 1
fi

if [ -n "${SAFE_ADDRESS:-}" ] && ! same_address "$SAFE_ADDRESS" "$PROXY_OWNER"; then
  echo "SAFE_ADDRESS ($SAFE_ADDRESS) does not match proxy owner ($PROXY_OWNER)."
  exit 1
fi

if [ -n "${UPGRADE_DELAY_EPOCHS:-}" ]; then
  ANNOUNCE_SIG="announceUpgradePlan(address,uint96)"
  ANNOUNCE_ARGS=("$NEW_PDP_VERIFIER_IMPLEMENTATION_ADDRESS" "$UPGRADE_DELAY_EPOCHS")
else
  ANNOUNCE_SIG="announcePlannedUpgrade((address,uint96))"
  ANNOUNCE_ARGS=("($NEW_PDP_VERIFIER_IMPLEMENTATION_ADDRESS,$AFTER_EPOCH)")
fi

ANNOUNCE_DATA=$(cast calldata "$ANNOUNCE_SIG" "${ANNOUNCE_ARGS[@]}")

if address_has_code "$PROXY_OWNER"; then
  print_contract_owner_tx "$ANNOUNCE_DATA"
  exit 0
fi

require_env "KEYSTORE"
require_env "PASSWORD"

ADDR=$(cast wallet address --keystore "$KEYSTORE" --password "$PASSWORD")
echo "Sending announcement from owner address: $ADDR"

if ! same_address "$PROXY_OWNER" "$ADDR"; then
  echo "Supplied KEYSTORE ($ADDR) is not the proxy owner ($PROXY_OWNER)."
  exit 1
fi

NONCE=$(cast nonce "$ADDR")

TX_HASH=$(cast send --keystore "$KEYSTORE" --password "$PASSWORD" "$PDP_VERIFIER_PROXY_ADDRESS" "$ANNOUNCE_SIG" "${ANNOUNCE_ARGS[@]}" \
  --nonce "$NONCE" \
  --json | jq -r '.transactionHash')

if [ -z "$TX_HASH" ]; then
  echo "Error: Failed to send $ANNOUNCE_SIG transaction"
  exit 1
fi

echo "$ANNOUNCE_SIG transaction sent: $TX_HASH"
if [ -n "${UPGRADE_DELAY_EPOCHS:-}" ]; then
  echo "Read nextUpgrade() after this executes to record the exact afterEpoch."
fi
