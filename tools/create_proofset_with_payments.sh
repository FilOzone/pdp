#!/bin/bash

# Check if required environment variables are set
if [ -z "$RPC_URL" ]; then
  echo "Error: RPC_URL is not set. Please set it to a valid Calibration testnet endpoint."
  echo "Example: export RPC_URL=https://api.calibration.node.glif.io/rpc/v1"
  exit 1
fi

if [ -z "$KEYSTORE" ]; then
  echo "Error: KEYSTORE is not set. Please set it to your Ethereum keystore path."
  exit 1
fi

# Print the RPC URL being used
echo "Using RPC URL: $RPC_URL"

# Set the contract addresses
PDP_VERIFIER_PROXY="0xC1Ded64818C89d12D624aF40E8E56dfe70F3fd3c"
PDP_SERVICE_PROXY="0xd3c54bFE267C4A7Baca91AdF1a6bbe3A5b36416d"
PAYMENTS_PROXY="0xdfD6960cB4221EcFf900A581f61156cb26EfDB84"
USDFC_TOKEN="0xb3042734b608a1B16e9e86B374A3f3e389B4cDf0"

# Get wallet address from keystore
MY_ADDRESS=$(cast wallet address --keystore "$KEYSTORE" --password "$PASSWORD")
echo "Using wallet address: $MY_ADDRESS"

# Get current nonce
CURRENT_NONCE=$(cast nonce --rpc-url "$RPC_URL" $MY_ADDRESS)
echo "Current nonce: $CURRENT_NONCE"

# Prepare the extraData for proofset creation (metadata and payer address)
# Format: (string metadata, address payer)
METADATA="My first proof set"
EXTRA_DATA=$(cast abi-encode "f((string,address))" "($METADATA,$MY_ADDRESS)")

# Check USDFC balance before
echo "Checking USDFC balance before approval and proofset creation..."
BALANCE_BEFORE=$(cast call --rpc-url "$RPC_URL" $USDFC_TOKEN "balanceOf(address)" $MY_ADDRESS)
echo "USDFC Balance before: $BALANCE_BEFORE"

# Check Payments contract internal balance before
echo "Checking Payments contract internal balance before..."
ACCOUNT_INFO_BEFORE=$(cast call --rpc-url "$RPC_URL" $PAYMENTS_PROXY "accounts(address,address)" $USDFC_TOKEN $MY_ADDRESS)
echo "Internal account balance before: $ACCOUNT_INFO_BEFORE"

# First, deposit USDFC into the Payments contract (this step is crucial!)
echo "Approving USDFC to be spent by Payments contract..."
APPROVE_TX=$(cast send --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" \
    $USDFC_TOKEN "approve(address,uint256)" $PAYMENTS_PROXY "1000000000000000000" \
    --gas-limit 3000000000 --nonce $CURRENT_NONCE)
echo "Approval TX: $APPROVE_TX"

# Wait for transaction to be mined
echo "Waiting for approval transaction to be mined..."
sleep 15

# Increment nonce for next transaction
CURRENT_NONCE=$((CURRENT_NONCE + 1))
echo "Next nonce: $CURRENT_NONCE"

# Actually deposit funds into the Payments contract
echo "Depositing USDFC into the Payments contract..."
DEPOSIT_TX=$(cast send --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" \
    $PAYMENTS_PROXY "deposit(address,address,uint256)" \
    $USDFC_TOKEN $MY_ADDRESS "1000000000000000000" \
    --gas-limit 3000000000 --nonce $CURRENT_NONCE)
echo "Deposit TX: $DEPOSIT_TX"

# Wait for transaction to be mined
echo "Waiting for deposit transaction to be mined..."
sleep 15

# Increment nonce for next transaction
CURRENT_NONCE=$((CURRENT_NONCE + 1))
echo "Next nonce: $CURRENT_NONCE"

# Check Payments contract internal balance after deposit
echo "Checking Payments contract internal balance after deposit..."
ACCOUNT_INFO_AFTER_DEPOSIT=$(cast call --rpc-url "$RPC_URL" $PAYMENTS_PROXY "accounts(address,address)" $USDFC_TOKEN $MY_ADDRESS)
echo "Internal account balance after deposit: $ACCOUNT_INFO_AFTER_DEPOSIT"

# Then set operator approval in the Payments contract for the PDP service
echo "Setting operator approval for the PDP service..."
OPERATOR_TX=$(cast send --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" \
    $PAYMENTS_PROXY "setOperatorApproval(address,address,bool,uint256,uint256)" \
    $USDFC_TOKEN $PDP_SERVICE_PROXY true "1000000000000000000" "1000000000000000000" \
    --gas-limit 3000000000 --nonce $CURRENT_NONCE)
echo "Operator approval TX: $OPERATOR_TX"

# Wait for transaction to be mined
echo "Waiting for operator approval transaction to be mined..."
sleep 15

# Increment nonce for next transaction
CURRENT_NONCE=$((CURRENT_NONCE + 1))
echo "Next nonce: $CURRENT_NONCE"

# Create the proof set
echo "Creating proof set..."
CALLDATA=$(cast calldata "createProofSet(address,bytes)" $PDP_SERVICE_PROXY $EXTRA_DATA)
CREATE_TX=$(cast send --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" \
    $PDP_VERIFIER_PROXY $CALLDATA --value "100000000000000000" --gas-limit 3000000000 --nonce $CURRENT_NONCE)
echo "Create proof set TX: $CREATE_TX"

# Wait for transaction to be mined
echo "Waiting for proof set creation transaction to be mined..."
sleep 15

# Get the latest proofset ID and rail ID
echo "Getting the latest proofset ID and rail ID..."
# Extract the ProofSetRailCreated event to get the IDs
LATEST_EVENTS=$(cast logs --rpc-url "$RPC_URL" --from-block "latest-50" --to-block latest $PDP_SERVICE_PROXY)
PROOFSET_ID=$(echo "$LATEST_EVENTS" | grep "ProofSetRailCreated" | tail -1 | cut -d' ' -f3)
RAIL_ID=$(echo "$LATEST_EVENTS" | grep "ProofSetRailCreated" | tail -1 | cut -d' ' -f4)
echo "Latest ProofSet ID: $PROOFSET_ID"
echo "Rail ID: $RAIL_ID"

# Check USDFC balance after
echo "Checking USDFC balance after proofset creation..."
BALANCE_AFTER=$(cast call --rpc-url "$RPC_URL" $USDFC_TOKEN "balanceOf(address)" $MY_ADDRESS)
echo "USDFC Balance after: $BALANCE_AFTER"

# Check Payments contract internal balance after proofset creation
echo "Checking Payments contract internal balance after proofset creation..."
ACCOUNT_INFO_AFTER=$(cast call --rpc-url "$RPC_URL" $PAYMENTS_PROXY "accounts(address,address)" $USDFC_TOKEN $MY_ADDRESS)
echo "Payer internal account balance after: $ACCOUNT_INFO_AFTER"

# Get the rail information to check who the payee is
echo "Getting rail information..."
if [ -n "$RAIL_ID" ]; then
    RAIL_INFO=$(cast call --rpc-url "$RPC_URL" $PAYMENTS_PROXY "getRail(uint256)" $RAIL_ID)
    echo "Rail info: $RAIL_INFO"
    PAYEE_ADDRESS=$(echo "$RAIL_INFO" | grep -A2 "to:" | tail -1 | tr -d ' ')
    echo "Payee address from rail: $PAYEE_ADDRESS"

    # Check payee's internal balance
    if [ -n "$PAYEE_ADDRESS" ]; then
        echo "Checking payee's internal balance in Payments contract..."
        PAYEE_BALANCE=$(cast call --rpc-url "$RPC_URL" $PAYMENTS_PROXY "accounts(address,address)" $USDFC_TOKEN $PAYEE_ADDRESS)
        echo "Payee internal balance: $PAYEE_BALANCE"
    else
        echo "Could not determine payee address"
    fi
else
    echo "Could not determine Rail ID"
fi

# Parse the account structs (funds,lockupCurrent,lockupRate,lockupLastSettledAt)
parse_account() {
  FUNDS=$(echo "$1" | cut -d',' -f1 | tr -d '(')
  LOCKUP_CURRENT=$(echo "$1" | cut -d',' -f2)
  LOCKUP_RATE=$(echo "$1" | cut -d',' -f3)
  LOCKUP_SETTLED=$(echo "$1" | cut -d',' -f4 | tr -d ')')
  
  echo "Funds: $FUNDS"
  echo "Lockup Current: $LOCKUP_CURRENT"
  echo "Lockup Rate: $LOCKUP_RATE"
  echo "Lockup Last Settled At: $LOCKUP_SETTLED"
}

echo "Payer account details before proofset creation:"
parse_account "$ACCOUNT_INFO_AFTER_DEPOSIT"

echo "Payer account details after proofset creation:"
parse_account "$ACCOUNT_INFO_AFTER"

if [ -n "$PAYEE_BALANCE" ]; then
    echo "Payee account details after proofset creation:"
    parse_account "$PAYEE_BALANCE"
fi

# Calculate the difference in payer funds
PAYER_FUNDS_BEFORE=$(echo "$ACCOUNT_INFO_AFTER_DEPOSIT" | cut -d',' -f1 | tr -d '(')
PAYER_FUNDS_AFTER=$(echo "$ACCOUNT_INFO_AFTER" | cut -d',' -f1 | tr -d '(')

if [ -n "$PAYER_FUNDS_BEFORE" ] && [ -n "$PAYER_FUNDS_AFTER" ]; then
    PAYER_FUNDS_BEFORE_DEC=$(cast --to-dec $PAYER_FUNDS_BEFORE)
    PAYER_FUNDS_AFTER_DEC=$(cast --to-dec $PAYER_FUNDS_AFTER)
    FUNDS_DIFFERENCE=$((PAYER_FUNDS_BEFORE_DEC - PAYER_FUNDS_AFTER_DEC))
    echo "Payer funds difference: $FUNDS_DIFFERENCE (should be approximately 100000000000000000 = 0.1 USDFC for the one-time payment)"
else
    echo "Could not calculate difference - fund values are empty"
fi

# Verify one-time payment occurred
if [ -n "$PAYEE_BALANCE" ]; then
    PAYEE_FUNDS=$(echo "$PAYEE_BALANCE" | cut -d',' -f1 | tr -d '(')
    if [ -n "$PAYEE_FUNDS" ]; then
        PAYEE_FUNDS_DEC=$(cast --to-dec $PAYEE_FUNDS)
        if [ "$PAYEE_FUNDS_DEC" -ge "100000000000000000" ]; then
            echo "✅ One-time payment verification: PASSED - Payee has received at least 0.1 USDFC"
        else
            echo "❌ One-time payment verification: FAILED - Payee has not received expected funds"
        fi
    else
        echo "❌ Could not verify one-time payment - payee fund value is empty"
    fi
else
    echo "❌ Could not verify one-time payment - payee balance could not be retrieved"
fi