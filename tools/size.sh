#!/bin/bash
# Usage: ./size.sh <contract-address> <data-set-id>
# Returns the total number of piece ids ever added to the data set

# Check if required environment variables are set
if [ -z "$RPC_URL" ] || [ -z "$KEYSTORE" ]; then
    echo "Error: Please set RPC_URL, KEYSTORE, and PASSWORD environment variables."
    exit 1
fi

# Check if data set ID is provided
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: <contract_address> <data_set_id>"
    exit 1
fi

CONTRACT_ADDRESS=$1
DATA_SET_ID=$2

# Create the calldata for getDataSetLeafCount(uint256)
CALLDATA=$(cast calldata "getNextPieceId(uint256)" $DATA_SET_ID)

# Call the contract and get the data set size
DATA_SET_SIZE=$(cast call --keystore $KEYSTORE --password "$PASSWORD" --rpc-url $RPC_URL $CONTRACT_ADDRESS $CALLDATA)
# Remove the "0x" prefix and convert the hexadecimal output to a decimal integer
DATA_SET_SIZE=$(echo $DATA_SET_SIZE | xargs printf "%d\n")

echo "Data set size: $DATA_SET_SIZE"