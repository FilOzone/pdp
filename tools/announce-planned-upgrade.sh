#!/bin/bash

# announce-planned-upgrade.sh: Announces a planned upgrade for PDPVerifier
# Required args: RPC_URL, PDP_VERIFIER_PROXY_ADDRESS, KEYSTORE, PASSWORD, NEW_PDP_VERIFIER_IMPLEMENTATION_ADDRESS, AFTER_EPOCH

if [ -z "$RPC_URL" ]; then
  echo "Error: RPC_URL is not set"
  exit 1
fi

if [ -z "$KEYSTORE" ]; then
  echo "Error: KEYSTORE is not set"
  exit 1
fi

if [ -z "$PASSWORD" ]; then
  echo "Error: PASSWORD is not set"
  exit 1
fi

if [ -z "$CHAIN" ]; then
  CHAIN=$(cast chain-id --rpc-url "$RPC_URL")
  if [ -z "$CHAIN" ]; then
    echo "Error: Failed to detect chain ID from RPC"
    exit 1
  fi
fi

if [ -z "$NEW_PDP_VERIFIER_IMPLEMENTATION_ADDRESS" ]; then
  echo "NEW_PDP_VERIFIER_IMPLEMENTATION_ADDRESS is not set"
  exit 1
fi

if [ -z "$AFTER_EPOCH" ]; then
  echo "AFTER_EPOCH is not set"
  exit 1
fi

CURRENT_EPOCH=$(cast block-number --rpc-url "$RPC_URL" 2>/dev/null)

if [ "$CURRENT_EPOCH" -gt "$AFTER_EPOCH" ]; then
  echo "Already past AFTER_EPOCH ($CURRENT_EPOCH > $AFTER_EPOCH)"
  exit 1
else
  echo "Announcing planned upgrade after $(($AFTER_EPOCH - $CURRENT_EPOCH)) epochs"
fi


ADDR=$(cast wallet address --keystore "$KEYSTORE" --password "$PASSWORD")
echo "Sending announcement from owner address: $ADDR"

# Get current nonce
NONCE=$(cast nonce --rpc-url "$RPC_URL" "$ADDR")

if [ -z "$PDP_VERIFIER_PROXY_ADDRESS" ]; then
  echo "Error: PDP_VERIFIER_PROXY_ADDRESS is not set"
  exit 1
fi

PROXY_OWNER=$(cast call --rpc-url "$RPC_URL" -f 0x0000000000000000000000000000000000000000 "$PDP_VERIFIER_PROXY_ADDRESS" "owner()(address)" 2>/dev/null)
if [ "$PROXY_OWNER" != "$ADDR" ]; then
  echo "Supplied KEYSTORE ($ADDR) is not the proxy owner ($PROXY_OWNER)."
  exit 1
fi

TX_HASH=$(cast send --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" "$PDP_VERIFIER_PROXY_ADDRESS" "announcePlannedUpgrade((address,uint96))" "($NEW_PDP_VERIFIER_IMPLEMENTATION_ADDRESS,$AFTER_EPOCH)" \
  --nonce "$NONCE" \
  --json | jq -r '.transactionHash')

if [ -z "$TX_HASH" ]; then
  echo "Error: Failed to send announcePlannedUpgrade transaction"
fi

echo "announcePlannedUpgrade transaction sent: $TX_HASH"

