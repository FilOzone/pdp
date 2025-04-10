#!/bin/bash
set -euo pipefail

#####################################
# Environment variables & defaults  #
#####################################

if [ -z "$RPC_URL" ]; then
  echo "Error: RPC_URL is not set"
  exit 1
fi

if [ -z "$KEYSTORE" ]; then
  echo "Error: KEYSTORE is not set"
  exit 1
fi

if [ -z "$CONTRACT_ADDRESS" ]; then
  echo "Error: CONTRACT_ADDRESS is not set"
  exit 1
fi

if [ -z "$NEW_OWNER" ]; then
  echo "Error: NEW_OWNER is not set"
  exit 1
fi

#####################################
# Setup                             #
#####################################
echo "Using keystore for authentication..."
ADDR=$(cast wallet address --keystore "$KEYSTORE" --password "$PASSWORD")
NONCE="$(cast nonce --rpc-url "$RPC_URL" "$ADDR")"
echo "Deployer address: $ADDR"
echo

#####################################
# Transfer ownership               #
#####################################
echo "Transferring ownership to new owner..."
echo "Proxy address: $CONTRACT_ADDRESS"
echo "New owner: $NEW_OWNER"

cast send --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" --nonce $NONCE "$CONTRACT_ADDRESS" "transferOwnership(address)" "$NEW_OWNER"

echo "✓ Ownership transfer transaction submitted"

# Verify the ownership transfer
echo "Verifying new owner..."
NEW_OWNER_ADDRESS=$(
  cast call \
    --rpc-url "$RPC_URL" \
    "$CONTRACT_ADDRESS" \
    "owner()(address)"
)

if [ "${NEW_OWNER_ADDRESS,,}" != "${NEW_OWNER,,}" ]; then
    echo "Failed to transfer ownership"
    echo "Expected new owner to be: ${NEW_OWNER}"
    echo "Got: ${NEW_OWNER_ADDRESS}"
    exit 1
fi

echo "✓ Ownership transferred successfully to ${NEW_OWNER}"
echo