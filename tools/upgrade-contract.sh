#! /bin/bash
# upgrade-contract upgrades proxy at $PROXY_ADDRESS to a new deployment of the implementation 
# of the contract at $IMPLEMENTATION_PATH (i.e. src/PDPService.sol:PDPService / src/PDPRecordKeeper.sol:PDPRecordKeeper)
# Assumption: KEYSTORE, PASSWORD, RPC_URL env vars are set to an appropriate eth keystore path and password
# and to a valid RPC_URL for the target network.
# Assumption: forge, cast, jq are in the PATH
#
# Set DRY_RUN=false to actually deploy and broadcast transactions (default is dry-run for safety)
DRY_RUN=${DRY_RUN:-true}

if [ "$DRY_RUN" = "true" ]; then
    echo "🧪 Running in DRY-RUN mode - simulation only, no actual deployment"
else
    echo "🚀 Running in DEPLOYMENT mode - will actually deploy and upgrade contracts"
fi

echo "Upgrading contract"

if [ -z "$RPC_URL" ]; then
  echo "Error: RPC_URL is not set"
  exit 1
fi

if [ -z "$CHAIN_ID" ]; then
  CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL")
  if [ -z "$CHAIN_ID" ]; then
    echo "Error: Failed to detect chain ID from RPC"
    exit 1
  fi
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

if [ "$DRY_RUN" = "true" ]; then
    echo "🔍 Simulating deployment of new $IMPLEMENTATION_PATH implementation contract"
    forge create --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" --compiler-version 0.8.23 --chain-id "$CHAIN_ID" "$IMPLEMENTATION_PATH"
    
    if [ $? -eq 0 ]; then
        echo "✅ Contract compilation and simulation successful!"
        echo "🔍 Simulating proxy upgrade at $PROXY_ADDRESS"
        echo "   - Would call: upgradeToAndCall(address,bytes)"
        echo "   - With upgrade data: $UPGRADE_DATA"
        echo "✅ Dry run completed successfully!"
        echo ""
        echo "To perform actual deployment, run with: DRY_RUN=false ./tools/upgrade-contract.sh"
    else
        echo "❌ Contract compilation failed during simulation"
        exit 1
    fi
else
    echo "🚀 Deploying new $IMPLEMENTATION_PATH implementation contract"
    # Parse the output of forge create to extract the contract address
    IMPLEMENTATION_ADDRESS=$(forge create --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" --broadcast --compiler-version 0.8.23 --chain-id "$CHAIN_ID" "$IMPLEMENTATION_PATH" | grep "Deployed to" | awk '{print $3}')

    if [ -z "$IMPLEMENTATION_ADDRESS" ]; then
        echo "❌ Error: Failed to extract PDP verifier contract address"
        exit 1
    fi
    echo "✅ $IMPLEMENTATION_PATH implementation deployed at: $IMPLEMENTATION_ADDRESS"

    echo "🔄 Upgrading proxy at $PROXY_ADDRESS"
    cast send --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" --chain-id "$CHAIN_ID" "$PROXY_ADDRESS" "upgradeToAndCall(address,bytes)" "$IMPLEMENTATION_ADDRESS" "$UPGRADE_DATA"
    
    if [ $? -eq 0 ]; then
        echo "✅ Contract upgrade completed successfully!"
        echo "📄 You can verify the upgrade by checking the VERSION:"
        echo "   cast call $PROXY_ADDRESS \"VERSION()\" --rpc-url $RPC_URL | cast --to-ascii"
    else
        echo "❌ Contract upgrade failed"
        exit 1
    fi
fi
