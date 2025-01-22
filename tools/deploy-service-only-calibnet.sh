#! /bin/bash
# deploy-pdp-service deploys only the PDP service contracts to calibration net
# Assumption: KEYSTORE, PASSWORD, RPC_URL env vars are set to an appropriate eth keystore path and password
# and to a valid RPC_URL for the devnet.
# Assumption: forge, cast, jq are in the PATH
# Assumption: called from contracts directory so forge paths work out
# Additional requirement: PDP_VERIFIER_ADDRESS environment variable must be set to an existing verifier address

echo "Deploying PDP Service to calibnet"

if [ -z "$RPC_URL" ]; then
  echo "Error: RPC_URL is not set"
  exit 1
fi

if [ -z "$KEYSTORE" ]; then
  echo "Error: KEYSTORE is not set"
  exit 1
fi

if [ -z "$PDP_VERIFIER_ADDRESS" ]; then
  echo "Error: PDP_VERIFIER_ADDRESS is not set"
  exit 1
fi

ADDR=$(cast wallet address --keystore "$KEYSTORE" --password "$PASSWORD")
echo "Deploying PDP Service from address $ADDR"

NONCE="$(cast nonce --rpc-url "$RPC_URL" "$ADDR")"
echo "Deploying PDP Service implementation"
SERVICE_IMPLEMENTATION_ADDRESS=$(forge create --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" --broadcast --nonce $NONCE --chain-id 314159 src/SimplePDPService.sol:SimplePDPService | grep "Deployed to" | awk '{print $3}')
if [ -z "$SERVICE_IMPLEMENTATION_ADDRESS" ]; then
    echo "Error: Failed to extract PDP service contract address"
    exit 1
fi
echo "PDP service implementation deployed at: $SERVICE_IMPLEMENTATION_ADDRESS"

echo "Deploying PDP Service proxy"
NONCE=$(expr $NONCE + "1")
INIT_DATA=$(cast calldata "initialize(address)" $PDP_VERIFIER_ADDRESS)
PDP_SERVICE_ADDRESS=$(forge create --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" --broadcast --nonce $NONCE --chain-id 314159 src/ERC1967Proxy.sol:MyERC1967Proxy --constructor-args $SERVICE_IMPLEMENTATION_ADDRESS $INIT_DATA | grep "Deployed to" | awk '{print $3}')
echo "PDP service deployed at: $PDP_SERVICE_ADDRESS"