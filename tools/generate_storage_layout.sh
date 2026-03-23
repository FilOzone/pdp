#!/bin/bash

echo // SPDX-License-Identifier: Apache-2.0 OR MIT
echo pragma solidity ^0.8.20\;
echo
echo // Code generated - DO NOT EDIT.
echo // This file is a generated binding and any changes will be lost.
echo // Generated with tools/generate_storage_layout.sh
echo

forge inspect --json $1 storageLayout \
    | jq -rM 'reduce .storage.[] as {$label,$slot} (null; . += "bytes32 constant " + (
            $label
                | [scan("[A-Z]+(?=[A-Z][a-z]|$)|[A-Z]?[a-z0-9]+")]
                | map(ascii_upcase)
                | join("_")
        ) + "_SLOT = bytes32(uint256(" + $slot + "));\n")'