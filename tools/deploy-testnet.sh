#! /bin/bash
# deploy-testnet deploys the PDP verifier and PDP service contracts to base sepolia testnet
# Assumption: KEYSTORE, PASSWORD, RPC_URL env vars are set to an appropriate eth keystore path and password
# and to a valid RPC_URL for the devnet.
# Assumption: forge, cast, jq are in the PATH
# Assumption: called from contracts directory so forge paths work out
#
echo "Deploying to calibnet"

if [ -z "$RPC_URL" ]; then
  echo "Error: RPC_URL is not set"
  exit 1
fi

if [ -z "$KEYSTORE" ]; then
  echo "Error: KEYSTORE is not set"
  exit 1
fi

# Calibration testnet uses 10 epochs (vs 150 on mainnet)
CHALLENGE_FINALITY=10
VERIFIER_INIT_COUNTER=1
ZERO_ADDRESS="0x0000000000000000000000000000000000000000"
USDFC_TOKEN_ADDRESS="${USDFC_TOKEN_ADDRESS:-0xb3042734b608a1B16e9e86B374A3f3e389B4cDf0}"
USDFC_SYBIL_FEE="${USDFC_SYBIL_FEE:-100000000000000000}"
PAYMENTS_CONTRACT_ADDRESS="${PAYMENTS_CONTRACT_ADDRESS:-0x09a0fDc2723fAd1A7b8e3e00eE5DF73841df55a0}"

ADDR=$(cast wallet address --keystore "$KEYSTORE" --password "$PASSWORD")
echo "Deploying PDP verifier from address $ADDR"
# Parse the output of forge create to extract the contract address

echo "PDPVerifier constructor args:"
echo "  initializerVersion: $VERIFIER_INIT_COUNTER"
echo "  USDFC_TOKEN_ADDRESS: $USDFC_TOKEN_ADDRESS"
echo "  USDFC_SYBIL_FEE: $USDFC_SYBIL_FEE"
echo "  PAYMENTS_CONTRACT_ADDRESS: $PAYMENTS_CONTRACT_ADDRESS"
if [ "$USDFC_TOKEN_ADDRESS" = "$ZERO_ADDRESS" ] || [ "$PAYMENTS_CONTRACT_ADDRESS" = "$ZERO_ADDRESS" ]; then
  echo "  note: USDFC-backed fee path disabled; deployment will use FIL fallback only"
fi

NONCE="$(cast nonce --rpc-url "$RPC_URL" "$ADDR")"
VERIFIER_IMPLEMENTATION_ADDRESS=$(forge create --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" --broadcast  --nonce $NONCE --chain-id 84532  src/PDPVerifier.sol:PDPVerifier --constructor-args "$VERIFIER_INIT_COUNTER" "$USDFC_TOKEN_ADDRESS" "$USDFC_SYBIL_FEE" "$PAYMENTS_CONTRACT_ADDRESS" | grep "Deployed to" | awk '{print $3}')
if [ -z "$VERIFIER_IMPLEMENTATION_ADDRESS" ]; then
    echo "Error: Failed to extract PDP verifier contract address"
    exit 1
fi
echo "PDP verifier implementation deployed at: $VERIFIER_IMPLEMENTATION_ADDRESS"
echo "Deploying PDP verifier proxy"
NONCE=$(expr $NONCE + "1")

INIT_DATA=$(cast calldata "initialize(uint256)" $CHALLENGE_FINALITY)
PDP_VERIFIER_ADDRESS=$(forge create --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" --broadcast --nonce $NONCE --chain-id 84532 src/ERC1967Proxy.sol:MyERC1967Proxy --constructor-args $VERIFIER_IMPLEMENTATION_ADDRESS $INIT_DATA | grep "Deployed to" | awk '{print $3}')
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
