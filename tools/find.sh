#! /bin/bash
# Usage: ./find.sh <contract-address> <data-set-id> <input-list>
# input-list is a comma separated list of uint256s representing leaf indices to search for
# Example: ./find.sh 0x067fd08940ba732C25c44423005D662BF95e6763 0 '[100,200]'
findCallData=$(cast calldata "findPieceIds(uint256,uint256[])((uint256,uint256)[])" $2 $3)
cast send --keystore $KEYSTORE --password "$PASSWORD" --rpc-url $RPC_URL $1 $findCallData
