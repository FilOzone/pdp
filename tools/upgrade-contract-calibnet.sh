#! /bin/bash
# upgrade-contract-calibnet upgrades proxy at $PROXY_ADDRESS to a new deployment of the implementation 
# of the contract at $IMPLEMENTATION_PATH (i.e. src/PDPService.sol:PDPService / src/PDPRecordKeeper.sol:PDPRecordKeeper)
# Assumption: KEYSTORE, PASSWORD, RPC_URL env vars are set to an appropriate eth keystore path and password
# and to a valid RPC_URL for the devnet.
# Assumption: forge, cast, jq are in the PATH
#
echo "Upgrading contract calibnet"

if [ -z "$RPC_URL" ]; then
  echo "Error: RPC_URL is not set"
  exit 1
fi

if [ -z "$KEYSTORE" ]; then
  echo "Error: KEYSTORE is not set"
  exit 1
fi

if [ -z "$PROXY_ADDRESS" ]; then
  echo "Error: PROXY_ADDRESS is not set"
  exit 1
fi

if [ -z "$UPGRADE_DATA" ]; then
  echo "Error: UPGRADE_DATA is not set"
  exit 1
fi

if [ -z "$IMPLEMENTATION_PATH" ]; then
  echo "Error: IMPLEMENTATION_PATH is not set (i.e. src/PDPService.sol:PDPService)"
  exit 1
fi

echo "Deploying new $IMPLEMENTATION_PATH implementation contract"
# Parse the output of forge create to extract the contract address
IMPLEMENTATION_ADDRESS=$(forge create --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" --compiler-version 0.8.30 --chain-id 314159 "$IMPLEMENTATION_PATH" | grep "Deployed to" | awk '{print $3}')

if [ -z "$IMPLEMENTATION_ADDRESS" ]; then
    echo "Error: Failed to extract PDP verifier contract address"
    exit 1
fi
echo "$IMPLEMENTATION_PATH implementation deployed at: $IMPLEMENTATION_ADDRESS"

echo "Upgrading proxy at $PROXY_ADDRESS"
cast send --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" --chain-id 314159 "$PROXY_ADDRESS" "upgradeToAndCall(address,bytes)" "$IMPLEMENTATION_ADDRESS" "$UPGRADE_DATA"
