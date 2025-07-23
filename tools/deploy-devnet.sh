#! /bin/bash
# deploy-devnet deploys the PDP service contract and all auxillary contracts to a filecoin devnet
# Assumption: KEYSTORE, PASSWORD, RPC_URL env vars are set to an appropriate eth keystore path and password
# and to a valid RPC_URL for the devnet.
# Assumption: forge, cast, lotus, jq are in the PATH
# Assumption: called from contracts directory so forge paths work out
#
echo "Deploying to devnet"

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
sleep 5 ## Sleep for 5 seconds so fund are available and actor is registered

NONCE="$(cast nonce --rpc-url "$RPC_URL" "$clientAddr")"

echo "Deploying PDP verifier"
# Parse the output of forge create to extract the contract address
VERIFIER_IMPLEMENTATION_ADDRESS=$(forge create --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" --nonce $NONCE --broadcast  src/PDPVerifier.sol:PDPVerifier | grep "Deployed to" | awk '{print $3}')
if [ -z "$VERIFIER_IMPLEMENTATION_ADDRESS" ]; then
    echo "Error: Failed to extract PDP verifier contract address"
    exit 1
fi
echo "PDP verifier implementation deployed at: $VERIFIER_IMPLEMENTATION_ADDRESS"

NONCE=$(expr $NONCE + "1")

echo "Deploying PDP verifier proxy"
INIT_DATA=$(cast calldata "initialize(uint256)" 150)
PDP_VERIFIER_ADDRESS=$(forge create --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" --nonce $NONCE --broadcast src/ERC1967Proxy.sol:MyERC1967Proxy --constructor-args $VERIFIER_IMPLEMENTATION_ADDRESS $INIT_DATA | grep "Deployed to" | awk '{print $3}')
echo "PDP verifier deployed at: $PDP_VERIFIER_ADDRESS"

echo ""
echo "================================================="
echo "DEPLOYMENT COMPLETE"
echo "================================================="
echo "PDPVerifier Implementation: $VERIFIER_IMPLEMENTATION_ADDRESS"
echo "PDPVerifier Proxy: $PDP_VERIFIER_ADDRESS"
echo ""
echo "NOTE: SimplePDPService is no longer deployed by default as of v2.0.0."
echo "      It remains available as a reference implementation in src/SimplePDPService.sol"
echo "      For community use and learning purposes."
echo ""
