#! /bin/bash
# deploy-devnet deploys the PDP verifier and PDP service contracts to calibration net
# Assumption: KEYSTORE, PASSWORD, RPC_URL env vars are set to an appropriate eth keystore path and password
# and to a valid RPC_URL for the devnet.
# Assumption: forge, cast, jq are in the PATH
# Assumption: called from contracts directory so forge paths work out
#
echo "Deploying to mainnet"

if [ -z "$RPC_URL" ]; then
  echo "Error: RPC_URL is not set"
  exit 1
fi

if [ -z "$KEYSTORE" ]; then
  echo "Error: KEYSTORE is not set"
  exit 1
fi

# CHALLENGE_FINALITY should always be 150 in production
CHALLENGE_FINALITY=150 

ADDR=$(cast wallet address --keystore "$KEYSTORE" --password "$PASSWORD")
echo "Deploying PDP verifier from address $ADDR"
# Parse the output of forge create to extract the contract address
 
NONCE="$(cast nonce --rpc-url "$RPC_URL" "$ADDR")"
VERIFIER_IMPLEMENTATION_ADDRESS=$(forge create --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" --broadcast  --nonce $NONCE --chain-id 314 src/PDPVerifier.sol:PDPVerifier | grep "Deployed to" | awk '{print $3}')
if [ -z "$VERIFIER_IMPLEMENTATION_ADDRESS" ]; then
    echo "Error: Failed to extract PDP verifier contract address"
    exit 1
fi
echo "PDP verifier implementation deployed at: $VERIFIER_IMPLEMENTATION_ADDRESS"
echo "Deploying PDP verifier proxy"
NONCE=$(expr $NONCE + "1")

INIT_DATA=$(cast calldata "initialize(uint256)" $CHALLENGE_FINALITY)
PDP_VERIFIER_ADDRESS=$(forge create --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" --broadcast --nonce $NONCE --chain-id 314 src/ERC1967Proxy.sol:MyERC1967Proxy --constructor-args $VERIFIER_IMPLEMENTATION_ADDRESS $INIT_DATA | grep "Deployed to" | awk '{print $3}')
echo "PDP verifier deployed at: $PDP_VERIFIER_ADDRESS"

echo "Deploying PDP Service"
NONCE=$(expr $NONCE + "1")
SERVICE_IMPLEMENTATION_ADDRESS=$(forge create --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" --broadcast --nonce $NONCE --chain-id 314 src/SimplePDPService.sol:SimplePDPService | grep "Deployed to" | awk '{print $3}')
if [ -z "$SERVICE_IMPLEMENTATION_ADDRESS" ]; then
    echo "Error: Failed to extract PDP service contract address"
    exit 1
fi
echo "PDP service implementation deployed at: $SERVICE_IMPLEMENTATION_ADDRESS"
echo "Deploying PDP Service proxy"
NONCE=$(expr $NONCE + "1")
INIT_DATA=$(cast calldata "initialize(address)" $PDP_VERIFIER_ADDRESS)
PDP_SERVICE_ADDRESS=$(forge create --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" --broadcast --nonce $NONCE --chain-id 314 src/ERC1967Proxy.sol:MyERC1967Proxy --constructor-args $SERVICE_IMPLEMENTATION_ADDRESS $INIT_DATA | grep "Deployed to" | awk '{print $3}')
echo "PDP service deployed at: $PDP_SERVICE_ADDRESS"
