#! /bin/bash
# upgrade-contract upgrades proxy at $PROXY_ADDRESS to a new deployment of the implementation 
# of the contract at $IMPLEMENTATION_PATH 
# Assumption: KEYSTORE, PASSWORD, RPC_URL env vars are set to an appropriate eth keystore path and password
# and to a valid RPC_URL for the target network.
# Assumption: forge, cast, jq are in the PATH
# Assumption: $IMPLEMENTATION_PATH points to PDPVerifier
#
# Set DRY_RUN=false to actually deploy and broadcast transactions (default is dry-run for safety)
DRY_RUN=${DRY_RUN:-true}
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
ZERO_ADDRESS="0x0000000000000000000000000000000000000000"
PDP_VERIFIER_IMPLEMENTATION_PATH="src/PDPVerifier.sol:PDPVerifier"

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

UPGRADE_INIT_COUNTER=$(expr "$("$SCRIPT_DIR/get-initialized-counter.sh" "$PROXY_ADDRESS")" + 1)
CONSTRUCTOR_ARGS=("$UPGRADE_INIT_COUNTER")

if [ "$IMPLEMENTATION_PATH" != "$PDP_VERIFIER_IMPLEMENTATION_PATH" ]; then
    echo "Error: Only PDPVerifier upgrades are supported. Got: $IMPLEMENTATION_PATH"
    exit 1
fi

case "$CHAIN_ID" in
    "314")
        USDFC_TOKEN_ADDRESS="${USDFC_TOKEN_ADDRESS:-0x80B98d3aa09ffff255c3ba4A241111Ff1262F045}"
        PAYMENTS_CONTRACT_ADDRESS="${PAYMENTS_CONTRACT_ADDRESS:-0x23b1e018F08BB982348b15a86ee926eEBf7F4DAa}"
        ;;
    "314159")
        USDFC_TOKEN_ADDRESS="${USDFC_TOKEN_ADDRESS:-0xb3042734b608a1B16e9e86B374A3f3e389B4cDf0}"
        PAYMENTS_CONTRACT_ADDRESS="${PAYMENTS_CONTRACT_ADDRESS:-0x09a0fDc2723fAd1A7b8e3e00eE5DF73841df55a0}"
        ;;
    "31415926")
        USDFC_TOKEN_ADDRESS="${USDFC_TOKEN_ADDRESS:-$ZERO_ADDRESS}"
        PAYMENTS_CONTRACT_ADDRESS="${PAYMENTS_CONTRACT_ADDRESS:-$ZERO_ADDRESS}"
        ;;
    *)
        echo "Error: Unsupported chain ID for default PDPVerifier constructor args"
        echo "Please set USDFC_TOKEN_ADDRESS and PAYMENTS_CONTRACT_ADDRESS explicitly."
        exit 1
        ;;
esac
USDFC_SYBIL_FEE="${USDFC_SYBIL_FEE:-100000000000000000}"
CONSTRUCTOR_ARGS=("$UPGRADE_INIT_COUNTER" "$USDFC_TOKEN_ADDRESS" "$USDFC_SYBIL_FEE" "$PAYMENTS_CONTRACT_ADDRESS")

echo "Using PDPVerifier constructor args:"
echo "  initializerVersion: $UPGRADE_INIT_COUNTER"
echo "  USDFC_TOKEN_ADDRESS: $USDFC_TOKEN_ADDRESS"
echo "  USDFC_SYBIL_FEE: $USDFC_SYBIL_FEE"
echo "  PAYMENTS_CONTRACT_ADDRESS: $PAYMENTS_CONTRACT_ADDRESS"
if [ "$USDFC_TOKEN_ADDRESS" = "$ZERO_ADDRESS" ] || [ "$PAYMENTS_CONTRACT_ADDRESS" = "$ZERO_ADDRESS" ]; then
    echo "  note: USDFC-backed fee path disabled; deployment will use FIL fallback only"
fi

if [ "$DRY_RUN" = "true" ]; then
    echo "🔍 Simulating deployment of new $IMPLEMENTATION_PATH implementation contract"
    forge create --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" --compiler-version 0.8.30 --chain-id "$CHAIN_ID"  "$IMPLEMENTATION_PATH" --constructor-args "${CONSTRUCTOR_ARGS[@]}"
    
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
    IMPLEMENTATION_ADDRESS=$(forge create --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" --broadcast --compiler-version 0.8.30 --chain-id "$CHAIN_ID"  "$IMPLEMENTATION_PATH" --constructor-args "${CONSTRUCTOR_ARGS[@]}" | grep "Deployed to" | awk '{print $3}')

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
