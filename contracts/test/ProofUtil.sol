// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Cids} from "../src/Cids.sol";
import {MerkleVerify, Hashes} from "../src/Proofs.sol";

// Methods for committing to data and generating proofs.
// These are only used in tests (which verify proofs).
// These functions provide a spec for the operations which providers should perform off-chain.
library ProofUtil {
    /** Generates an array of leaves with distinct values. */
    function generateLeaves(uint256 count) internal pure returns (bytes32[] memory) {
        bytes32[] memory result = new bytes32[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = bytes32(i);
        }
        return result;
    }

}