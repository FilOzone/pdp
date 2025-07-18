#! /bin/bash
# Usage: ./remove.sh <contract-address> <data-set-id> <input-list>
# input-list is a comma separated list of uint256s representing piece ids to remove
removeCallData=$(cast calldata "removePieces(uint256,uint256[])(uint256)" $2 $3)
cast send --keystore $KEYSTORE --password "$PASSWORD" --rpc-url $RPC_URL $1 $removeCallData
