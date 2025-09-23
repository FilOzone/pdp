// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {PDPVerifier} from "../src/PDPVerifier.sol";
import {MerkleProve} from "../src/Proofs.sol";
import {IPDPTypes} from "../src/interfaces/IPDPTypes.sol";

contract ProofBuilderHelper is Test {
    // Builds a proof of possession for a data set
    function buildProofs(
        PDPVerifier pdpVerifier,
        uint256 setId,
        uint256 challengeCount,
        bytes32[][][] memory trees,
        uint256[] memory leafCounts
    ) internal view returns (IPDPTypes.Proof[] memory) {
        uint256 challengeEpoch = pdpVerifier.getNextChallengeEpoch(setId);
        uint256 seed = challengeEpoch; // Seed is (temporarily) the challenge epoch
        uint256 totalLeafCount = 0;
        for (uint256 i = 0; i < leafCounts.length; ++i) {
            totalLeafCount += leafCounts[i];
        }

        IPDPTypes.Proof[] memory proofs = new IPDPTypes.Proof[](challengeCount);
        for (uint256 challengeIdx = 0; challengeIdx < challengeCount; challengeIdx++) {
            // Compute challenge index
            bytes memory payload = abi.encodePacked(seed, setId, uint64(challengeIdx));
            uint256 challengeOffset = uint256(keccak256(payload)) % totalLeafCount;

            uint256 treeIdx = 0;
            uint256 treeOffset = 0;
            for (uint256 i = 0; i < leafCounts.length; ++i) {
                if (leafCounts[i] > challengeOffset) {
                    treeIdx = i;
                    treeOffset = challengeOffset;
                    break;
                } else {
                    challengeOffset -= leafCounts[i];
                }
            }

            bytes32[][] memory tree = trees[treeIdx];
            bytes32[] memory path = MerkleProve.buildProof(tree, treeOffset);
            proofs[challengeIdx] = IPDPTypes.Proof(tree[tree.length - 1][treeOffset], path);

            // console.log("Leaf", vm.toString(proofs[0].leaf));
            // console.log("Proof");
            // for (uint j = 0; j < proofs[0].proof.length; j++) {
            //     console.log(vm.toString(j), vm.toString(proofs[0].proof[j]));
            // }
        }

        return proofs;
    }
}
