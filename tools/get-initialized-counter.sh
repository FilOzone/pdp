#!/bin/bash
#
# Reads the current reinitializer counter from an OpenZeppelin
# Initializable proxy contract.
#
# The counter lives in the InitializableStorage struct at the
# ERC-7201 namespaced slot defined in:
# https://github.com/OpenZeppelin/openzeppelin-contracts/blob/dde766bd542e4a1695fe8e4a07dc03b77305f367/contracts/proxy/utils/Initializable.sol#L76-L77

if [ -z "$RPC_URL" ]; then
    echo "Error: RPC_URL is not set"
    exit 1
fi

if [ -z "$1" ]; then
    echo "Error: Must specify a contract address"
    exit 1
fi

# keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Initializable")) - 1)) & ~bytes32(uint256(0xff))
INITIALIZABLE_STORAGE="0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00"
SLOT=$(cast storage --rpc-url "$RPC_URL" $1 $INITIALIZABLE_STORAGE)

cast to-base $SLOT 10