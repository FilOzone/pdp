#!/bin/bash
# deploy-simple-pdp-service.sh - Optional deployment script for SimplePDPService
# 
# ⚠️  DEPRECATED as of v2.0.0 ⚠️
# SimplePDPService is no longer actively maintained but remains available
# as a reference implementation for the community.
#
# This script deploys SimplePDPService to work with an existing PDPVerifier.
# 
# Prerequisites:
# - PDPVerifier must already be deployed
# - Set PDP_VERIFIER_ADDRESS environment variable to the PDPVerifier proxy address
# - Set RPC_URL, KEYSTORE, PASSWORD environment variables
#
# Usage:
#   export PDP_VERIFIER_ADDRESS=0x...
#   export RPC_URL=https://...
#   export KEYSTORE=/path/to/keystore
#   export PASSWORD=your_password
#   ./deploy-simple-pdp-service.sh

echo "================================================="
echo "⚠️  DEPRECATED: SimplePDPService Deployment ⚠️"
echo "================================================="
echo ""
echo "SimplePDPService is no longer actively maintained as of v2.0.0."
echo "This script is provided for reference and community use only."
echo ""
echo "Consider implementing your own service layer using PDPVerifier directly."
echo "See src/SimplePDPService.sol as a reference implementation."
echo ""
read -p "Do you want to continue with SimplePDPService deployment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled."
    exit 0
fi

echo ""
echo "Proceeding with SimplePDPService deployment..."

# Validate required environment variables
if [ -z "$PDP_VERIFIER_ADDRESS" ]; then
  echo "Error: PDP_VERIFIER_ADDRESS is not set"
  echo "Please set it to your deployed PDPVerifier proxy address"
  exit 1
fi

if [ -z "$RPC_URL" ]; then
  echo "Error: RPC_URL is not set"
  exit 1
fi

if [ -z "$KEYSTORE" ]; then
  echo "Error: KEYSTORE is not set"
  exit 1
fi

# Determine chain ID based on RPC URL
CHAIN_ID=314  # Default to mainnet
if [[ "$RPC_URL" == *"calibration"* ]]; then
    CHAIN_ID=314159
fi

ADDR=$(cast wallet address --keystore "$KEYSTORE" --password "$PASSWORD")
echo "Deploying SimplePDPService from address $ADDR"
echo "Using PDPVerifier at: $PDP_VERIFIER_ADDRESS"

NONCE="$(cast nonce --rpc-url "$RPC_URL" "$ADDR")"

echo "Deploying SimplePDPService implementation..."
SERVICE_IMPLEMENTATION_ADDRESS=$(forge create --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" --broadcast --nonce $NONCE --chain-id $CHAIN_ID src/SimplePDPService.sol:SimplePDPService | grep "Deployed to" | awk '{print $3}')

if [ -z "$SERVICE_IMPLEMENTATION_ADDRESS" ]; then
    echo "Error: Failed to extract SimplePDPService contract address"
    exit 1
fi

echo "SimplePDPService implementation deployed at: $SERVICE_IMPLEMENTATION_ADDRESS"

NONCE=$(expr $NONCE + "1")

echo "Deploying SimplePDPService proxy..."
INIT_DATA=$(cast calldata "initialize(address)" $PDP_VERIFIER_ADDRESS)
PDP_SERVICE_ADDRESS=$(forge create --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" --broadcast --nonce $NONCE --chain-id $CHAIN_ID src/ERC1967Proxy.sol:MyERC1967Proxy --constructor-args $SERVICE_IMPLEMENTATION_ADDRESS $INIT_DATA | grep "Deployed to" | awk '{print $3}')

if [ -z "$PDP_SERVICE_ADDRESS" ]; then
    echo "Error: Failed to deploy SimplePDPService proxy"
    exit 1
fi

echo ""
echo "================================================="
echo "SimplePDPService DEPLOYMENT COMPLETE"
echo "================================================="
echo "SimplePDPService Implementation: $SERVICE_IMPLEMENTATION_ADDRESS"
echo "SimplePDPService Proxy: $PDP_SERVICE_ADDRESS"
echo "Connected to PDPVerifier: $PDP_VERIFIER_ADDRESS"
echo ""
echo "⚠️  Remember: SimplePDPService is deprecated and not actively maintained."
echo "   Consider migrating to a custom service implementation."
echo ""