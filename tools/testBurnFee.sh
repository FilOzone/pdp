#! /bin/bash
# deploy-devnet deploys the PDP service contract and all auxillary contracts to a filecoin devnet
# Assumption: KEYSTORE, PASSWORD, RPC_URL env vars are set to an appropriate eth keystore path and password
# and to a valid RPC_URL for the devnet.
# Assumption: forge, cast, lotus, jq are in the PATH
#
echo "Deploying To Test Burn Fee"

if [ -z "$RPC_URL" ]; then
  echo "Error: RPC_URL is not set"
  exit 1
fi

if [ -z "$KEYSTORE" ]; then
  echo "Error: KEYSTORE is not set"
  exit 1
fi

# Send funds from default to keystore address
# assumes lotus binary in path
clientAddr=$(cat $KEYSTORE | jq '.address' | sed -e 's/\"//g')
echo "Sending funds to $clientAddr"
lotus send $clientAddr 10000

# Deploy PDP service contract
echo "Deploying PDP service"
# Parse the output of forge create to extract the contract address
PDP_SERVICE_ADDRESS=$(forge create --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" --compiler-version 0.8.23 --chain-id 31415926 contracts/src/PDPService.sol:PDPService --constructor-args 3 | grep "Deployed to" | awk '{print $3}')

if [ -z "$PDP_SERVICE_ADDRESS" ]; then
    echo "Error: Failed to extract PDP service contract address"
    exit 1
fi

echo "PDP service deployed at: $PDP_SERVICE_ADDRESS"

echo "Executing burnFee function"

# Create the calldata for burnFee()
CALLDATA=$(cast calldata "burnFee(uint256 amount)" 1)

# Send the transaction
cast send --keystore $KEYSTORE --password "$PASSWORD" --rpc-url $RPC_URL $PDP_SERVICE_ADDRESS $CALLDATA --value 1
