#!/bin/bash
# claim_ownership.sh - Script for claiming ownership of a proofset

# Check if correct number of arguments provided
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <proofset_id>"
  exit 1
fi

# Get argument
PROOFSET_ID=$1

# Check required environment variables
if [ -z "$PASSWORD" ] || [ -z "$KEYSTORE" ] || [ -z "$RPC_URL" ] || [ -z "$CONTRACT_ADDRESS" ]; then
  echo "Error: Missing required environment variables."
  echo "Please set PASSWORD, KEYSTORE, RPC_URL, and CONTRACT_ADDRESS."
  exit 1
fi

echo "Claiming ownership of proofset ID: $PROOFSET_ID"

# Get claimer's address from keystore
CLAIMER_ADDRESS=$(cast wallet address --keystore "$KEYSTORE")
echo "New owner address (claiming ownership): $CLAIMER_ADDRESS"

# Construct calldata using cast calldata
CALLDATA=$(cast calldata "claimProofSetOwnership(uint256)" "$PROOFSET_ID")

echo "Sending transaction..."

# Send transaction
TX_HASH=$(cast send --rpc-url "$RPC_URL" \
  --keystore "$KEYSTORE" \
  --password "$PASSWORD" \
  "$CONTRACT_ADDRESS" \
  "$CALLDATA")

echo "Transaction sent! Hash: $TX_HASH"
echo "Successfully claimed ownership of proofset $PROOFSET_ID"