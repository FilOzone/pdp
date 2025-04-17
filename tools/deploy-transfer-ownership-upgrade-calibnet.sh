#!/usr/bin/env bash
set -euo pipefail

#####################################
# Environment variables & defaults  #
#####################################

: "${FIL_CALIBNET_RPC_URL:?FIL_CALIBNET_RPC_URL not set. Please export it and rerun.}"
: "${FIL_CALIBNET_PRIVATE_KEY:?FIL_CALIBNET_PRIVATE_KEY not set. Please export it and rerun.}"
: "${NEW_OWNER:?NEW_OWNER not set. Please export it and rerun.}"


CHAIN_ID="${CHAIN_ID:-314159}"
COMPILER_VERSION="${COMPILER_VERSION:-0.8.30}"

#####################################
# 1. Create INIT_DATA               #
#####################################
echo "Generating calldata for initialize(uint256) with argument 150 ..."
INIT_DATA=$(cast calldata "initialize(uint256)" 150)
echo "INIT_DATA = $INIT_DATA"
echo

#####################################
# 1. Get deployer address           #
#####################################
echo "Deriving deployer address from private key ..."
DEPLOYER_ADDRESS=$(cast wallet address "$FIL_CALIBNET_PRIVATE_KEY")
NONCE="$(cast nonce --rpc-url "$FIL_CALIBNET_RPC_URL" "$DEPLOYER_ADDRESS")"
echo "Deployer address: $DEPLOYER_ADDRESS"
echo

#####################################
# 2. Deploy PDPVerifier contract    #
#####################################
echo "Deploying PDPVerifier contract ..."
DEPLOY_OUTPUT_VERIFIER=$(
  forge create \
    --rpc-url "$FIL_CALIBNET_RPC_URL" \
    --private-key "$FIL_CALIBNET_PRIVATE_KEY" \
    --chain-id "$CHAIN_ID" \
    --broadcast \
    --nonce $NONCE \
    src/PDPVerifier.sol:PDPVerifier
)
NONCE=$(expr $NONCE + "1")


# Extract the deployed address from JSON output
PDP_VERIFIER_ADDRESS=$(echo "$DEPLOY_OUTPUT_VERIFIER" | grep "Deployed to" | awk '{print $3}')
echo "PDPVerifier deployed at: $PDP_VERIFIER_ADDRESS"
echo

#####################################
# 3. Deploy Proxy contract          #
#####################################
echo "Deploying Proxy contract (MyERC1967Proxy) ..."
DEPLOY_OUTPUT_PROXY=$(forge create --rpc-url "$FIL_CALIBNET_RPC_URL"   --private-key "$FIL_CALIBNET_PRIVATE_KEY" --chain-id "$CHAIN_ID" --broadcast --nonce $NONCE src/ERC1967Proxy.sol:MyERC1967Proxy --constructor-args "$PDP_VERIFIER_ADDRESS" "$INIT_DATA")
NONCE=$(expr $NONCE + "1")


# Extract the deployed proxy address
PROXY_ADDRESS=$(echo "$DEPLOY_OUTPUT_PROXY" | grep "Deployed to" | awk '{print $3}')
echo "Proxy deployed at: $PROXY_ADDRESS"
echo

#####################################
# 4. Check owner of proxy           #
#####################################
echo "Querying the proxy's owner ..."
OWNER_ADDRESS=$(
  cast call \
    --rpc-url "$FIL_CALIBNET_RPC_URL" \
    "$PROXY_ADDRESS" \
    "owner()(address)"
)
echo "Proxy owner: $OWNER_ADDRESS"

# Add validation check
if [ "${OWNER_ADDRESS,,}" != "${DEPLOYER_ADDRESS,,}" ]; then
    echo "failed to validate owner address"
    echo "Expected owner to be: ${DEPLOYER_ADDRESS}"
    echo "Got: ${OWNER_ADDRESS}"
    exit 1
fi
echo "✓ Owner address validated successfully"
echo

#####################################
# 5. Check implementation address    #
#####################################
# The storage slot for ERC1967 implementation:
IMPLEMENTATION_SLOT="0x360894A13BA1A3210667C828492DB98DCA3E2076CC3735A920A3CA505D382BBC"

echo "Checking proxy's implementation address from storage slot $IMPLEMENTATION_SLOT ..."
sleep 35
IMPLEMENTATION_ADDRESS=$(cast storage --rpc-url "$FIL_CALIBNET_RPC_URL" "$PROXY_ADDRESS" "$IMPLEMENTATION_SLOT")

echo "Implementation address in Proxy: $IMPLEMENTATION_ADDRESS"
echo


#####################################
# Summary                           #
#####################################
echo "========== DEPLOYMENT SUMMARY =========="
echo "PDPVerifier Address:          $PDP_VERIFIER_ADDRESS"
echo "Proxy Address:                $PROXY_ADDRESS"
echo "Proxy Owner (should match deployer):  $OWNER_ADDRESS"
echo "PDPVerifier Implementation (via Proxy): $IMPLEMENTATION_ADDRESS"
echo "========================================"


#####################################
# 6. Upgrade proxy                  #
#####################################

echo "Deploying a new PDPVerifier contract ..."
DEPLOY_OUTPUT_VERIFIER_2=$(forge create --nonce $NONCE --broadcast --rpc-url "$FIL_CALIBNET_RPC_URL" --private-key "$FIL_CALIBNET_PRIVATE_KEY" --chain-id "$CHAIN_ID" src/PDPVerifier.sol:PDPVerifier)
NONCE=$(expr $NONCE + "1")
PDP_VERIFIER_ADDRESS_2=$(echo "$DEPLOY_OUTPUT_VERIFIER_2" | grep "Deployed to" | awk '{print $3}')
echo "PDPVerifier deployed at: $PDP_VERIFIER_ADDRESS_2"
echo

echo
echo "Upgrading proxy to new implementation..."

cast send --rpc-url "$FIL_CALIBNET_RPC_URL" --private-key "$FIL_CALIBNET_PRIVATE_KEY" --nonce $NONCE --chain-id "$CHAIN_ID" "$PROXY_ADDRESS" "upgradeToAndCall(address,bytes)" "$PDP_VERIFIER_ADDRESS_2" "0x"
NONCE=$(expr $NONCE + "1")

echo "✓ Upgrade transaction submitted"

# Verify the upgrade
echo "Verifying new implementation..."
sleep 35
NEW_IMPLEMENTATION_ADDRESS=$(cast storage --rpc-url "$FIL_CALIBNET_RPC_URL" "$PROXY_ADDRESS" "$IMPLEMENTATION_SLOT")

if [ "${NEW_IMPLEMENTATION_ADDRESS,,}" != "${PDP_VERIFIER_ADDRESS_2,,}" ]; then
    echo "failed to upgrade implementation"
    echo "Expected new implementation to be: ${PDP_VERIFIER_ADDRESS_2}"
    echo "Got: ${NEW_IMPLEMENTATION_ADDRESS}"
    exit 1
fi

echo "✓ Proxy upgraded successfully to ${PDP_VERIFIER_ADDRESS_2}"
echo

#####################################
# 7. Transfer ownership            #
#####################################
echo
echo "Transferring ownership to new owner..."

cast send --rpc-url "$FIL_CALIBNET_RPC_URL" --private-key "$FIL_CALIBNET_PRIVATE_KEY" --nonce $NONCE --chain-id "$CHAIN_ID" "$PROXY_ADDRESS" "transferOwnership(address)" "$NEW_OWNER"
NONCE=$(expr $NONCE + "1")

echo "✓ Ownership transfer transaction submitted"

# Verify the ownership transfer
echo "Verifying new owner..."
NEW_OWNER_ADDRESS=$(
  cast call \
    --rpc-url "$FIL_CALIBNET_RPC_URL" \
    "$PROXY_ADDRESS" \
    "owner()(address)"
)

if [ "${NEW_OWNER_ADDRESS,,}" != "${NEW_OWNER,,}" ]; then
    echo "failed to transfer ownership"
    echo "Expected new owner to be: ${NEW_OWNER}"
    echo "Got: ${NEW_OWNER_ADDRESS}"
    exit 1
fi

echo "✓ Ownership transferred successfully to ${NEW_OWNER}"
echo
