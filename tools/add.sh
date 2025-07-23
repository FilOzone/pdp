#! /bin/bash
# Usage: ./add.sh <contract-address> <data-set-id> <add-input-list>
# add-input-list is a comma separated list of tuples of the form ((bytes),uint256)
# Example: ./add.sh 0x067fd08940ba732C25c44423005D662BF95e6763 0 '[((0x000181E20392202070FB4C14254CE86AB762E0280E469AF4E01B34A1B4B08F75C258F197798EE33C),256)]'
addCallData=$(cast calldata "addPieces(uint256,((bytes),uint256)[])(uint256)" $2 $3)

cast send --keystore $KEYSTORE --password "$PASSWORD" --rpc-url $RPC_URL $1 $addCallData
