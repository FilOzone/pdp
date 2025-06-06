#!/bin/bash
# propose_owner.sh - Script for proposing a new owner for a proofset

# Check if correct number of arguments provided
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <proofset_id> <new_owner_address>"
  exit 1
fi

# Get arguments
PROOFSET_ID=$1
NEW_OWNER_ADDRESS=$2

# Check required environment variables
if [ -z "$PASSWORD" ] || [ -z "$KEYSTORE" ] || [ -z "$RPC_URL" ] || [ -z "$CONTRACT_ADDRESS" ]; then
  echo "Error: Missing required environment variables."
  echo "Please set PASSWORD, KEYSTORE, RPC_URL, and CONTRACT_ADDRESS."
  exit 1
fi

echo "Proposing new owner for proofset ID: $PROOFSET_ID"
echo "New owner address: $NEW_OWNER_ADDRESS"

# Get sender's address from keystore
SENDER_ADDRESS=$(cast wallet address --keystore "$KEYSTORE")
echo "Current owner address: $SENDER_ADDRESS"

# Construct calldata using cast calldata
CALLDATA=$(cast calldata "proposeProofSetOwner(uint256,address)" "$PROOFSET_ID" "$NEW_OWNER_ADDRESS")

echo "Sending transaction..."

# Send transaction
TX_HASH=$(cast send --rpc-url "$RPC_URL" \
  --keystore "$KEYSTORE" \
  --password "$PASSWORD" \
  "$CONTRACT_ADDRESS" \
  "$CALLDATA")

echo "Transaction sent! Hash: $TX_HASH"
echo "Successfully proposed $NEW_OWNER_ADDRESS as new owner for proofset $PROOFSET_ID"