// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.13;

import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import {Test, console, Vm} from "forge-std/Test.sol";
import {Cids} from "../src/Cids.sol";
import {PDPVerifier, PDPListener} from "../src/PDPVerifier.sol";
import {MyERC1967Proxy} from "../src/ERC1967Proxy.sol";
import {MerkleProve} from "../src/Proofs.sol";
import {ProofUtil} from "./ProofUtil.sol";
import {PDPFees} from "../src/Fees.sol";
import {SimplePDPService, PDPRecordKeeper} from "../src/SimplePDPService.sol";
import {IPDPTypes} from "../src/interfaces/IPDPTypes.sol";
import {IPDPEvents} from "../src/interfaces/IPDPEvents.sol";
import {PieceHelper} from "./PieceHelper.t.sol";

contract ProofBuilderHelper is Test {
    // Builds a proof of possession for a data set
    function buildProofs(PDPVerifier pdpVerifier, uint256 setId, uint challengeCount, bytes32[][][] memory trees, uint[] memory leafCounts) internal view returns (IPDPTypes.Proof[] memory) {
        uint256 challengeEpoch = pdpVerifier.getNextChallengeEpoch(setId);
        uint256 seed = challengeEpoch; // Seed is (temporarily) the challenge epoch
        uint totalLeafCount = 0;
        for (uint i = 0; i < leafCounts.length; ++i) {
            totalLeafCount += leafCounts[i];
        }

        IPDPTypes.Proof[] memory proofs = new IPDPTypes.Proof[](challengeCount);
        for (uint challengeIdx = 0; challengeIdx < challengeCount; challengeIdx++) {
            // Compute challenge index
            bytes memory payload = abi.encodePacked(seed, setId, uint64(challengeIdx));
            uint256 challengeOffset = uint256(keccak256(payload)) % totalLeafCount;

            uint treeIdx = 0;
            uint256 treeOffset = 0;
            for (uint i = 0; i < leafCounts.length; ++i) {
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
