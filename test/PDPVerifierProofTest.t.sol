// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.13;

import {MockFVMTest} from "fvm-solidity/mocks/MockFVMTest.sol";
import {Cids} from "../src/Cids.sol";
import {PDPVerifier} from "../src/PDPVerifier.sol";
import {MyERC1967Proxy} from "../src/ERC1967Proxy.sol";
import {ProofUtil} from "./ProofUtil.sol";
import {PDPFees} from "../src/Fees.sol";
import {IPDPTypes} from "../src/interfaces/IPDPTypes.sol";
import {IPDPEvents} from "../src/interfaces/IPDPEvents.sol";
import {PieceHelper} from "./PieceHelper.t.sol";
import {ProofBuilderHelper} from "./ProofBuilderHelper.t.sol";
import {TestingRecordKeeperService} from "./PDPVerifier.t.sol";
import {NEW_DATA_SET_SENTINEL} from "../src/PDPVerifier.sol";

contract PDPVerifierProofTest is MockFVMTest, ProofBuilderHelper, PieceHelper {
    uint256 constant CHALLENGE_FINALITY_DELAY = 2;
    bytes empty = new bytes(0);
    PDPVerifier pdpVerifier;
    TestingRecordKeeperService listener;

    function setUp() public override {
        super.setUp();
        PDPVerifier pdpVerifierImpl = new PDPVerifier();
        bytes memory initializeData = abi.encodeWithSelector(PDPVerifier.initialize.selector, CHALLENGE_FINALITY_DELAY);
        MyERC1967Proxy proxy = new MyERC1967Proxy(address(pdpVerifierImpl), initializeData);
        pdpVerifier = PDPVerifier(address(proxy));
        listener = new TestingRecordKeeperService();
        vm.fee(1 wei);
        vm.deal(address(pdpVerifierImpl), 100 ether);
    }

    function testProveSinglePiece() public {
        uint256 leafCount = 10;
        (uint256 setId, bytes32[][] memory tree) = makeDataSetWithOnePiece(leafCount);

        // Advance chain until challenge epoch.
        uint256 challengeEpoch = pdpVerifier.getNextChallengeEpoch(setId);
        vm.roll(challengeEpoch);

        // Build a proof with  multiple challenges to single tree.
        uint256 challengeCount = 3;
        IPDPTypes.Proof[] memory proofs = buildProofsForSingleton(setId, challengeCount, tree, leafCount);

        // Submit proof.
        RANDOMNESS_PRECOMPILE.mockBeaconRandomness(challengeEpoch, challengeEpoch);
        vm.expectEmit(true, true, false, false);
        IPDPTypes.PieceIdAndOffset[] memory challenges = new IPDPTypes.PieceIdAndOffset[](challengeCount);
        for (uint256 i = 0; i < challengeCount; i++) {
            challenges[i] = IPDPTypes.PieceIdAndOffset(0, 0);
        }
        emit IPDPEvents.PossessionProven(setId, challenges);
        pdpVerifier.provePossession{value: 1e18}(setId, proofs);

        // Verify the next challenge is in a subsequent epoch.
        // Next challenge unchanged by prove
        assertEq(pdpVerifier.getNextChallengeEpoch(setId), challengeEpoch);

        // Verify the next challenge is in a subsequent epoch after nextProvingPeriod
        pdpVerifier.nextProvingPeriod(setId, vm.getBlockNumber() + CHALLENGE_FINALITY_DELAY, empty);

        assertEq(pdpVerifier.getNextChallengeEpoch(setId), vm.getBlockNumber() + CHALLENGE_FINALITY_DELAY);
    }

    receive() external payable {}

    event Debug(string message, uint256 value);

    function testProveWithDifferentFeeAmounts() public {
        vm.fee(0 gwei);

        address sender = makeAddr("sender");
        vm.deal(sender, 1000 ether);
        vm.startPrank(sender);

        uint256 leafCount = 10;
        (uint256 setId, bytes32[][] memory tree) = makeDataSetWithOnePiece(leafCount);

        // Advance chain until challenge epoch.
        uint256 challengeEpoch = pdpVerifier.getNextChallengeEpoch(setId);
        vm.roll(challengeEpoch);

        RANDOMNESS_PRECOMPILE.mockBeaconRandomness(challengeEpoch, challengeEpoch);

        // Build a proof with multiple challenges to single tree.
        uint256 challengeCount = 3;
        IPDPTypes.Proof[] memory proofs = buildProofsForSingleton(setId, challengeCount, tree, leafCount);

        // Mock block.number to 2881
        vm.roll(2881);

        // Determine the correct fee.
        uint256 correctFee;
        {
            uint256 snapshotId = vm.snapshotState();
            uint256 balanceBefore = sender.balance;
            pdpVerifier.provePossession{value: sender.balance}(setId, proofs);
            uint256 balanceAfter = sender.balance;
            correctFee = balanceBefore - balanceAfter;
            vm.revertToStateAndDelete(snapshotId);
        }

        // Test 1: Sending less than the required fee
        vm.expectRevert("Incorrect fee amount");
        pdpVerifier.provePossession{value: correctFee - 1}(setId, proofs);

        // Test 2: Sending more than the required fee
        RANDOMNESS_PRECOMPILE.mockBeaconRandomness(challengeEpoch, challengeEpoch);
        pdpVerifier.provePossession{value: correctFee + 1}(setId, proofs);

        // Verify that the proof was accepted
        assertEq(
            pdpVerifier.getNextChallengeEpoch(setId),
            challengeEpoch,
            "Next challenge epoch should remain unchanged after prove"
        );
    }

    function testDataSetLastProvenEpochOnPieceRemoval() public {
        // Create a data set and verify initial lastProvenEpoch is 0
        uint256 setId = pdpVerifier.addPieces{value: PDPFees.sybilFee()}(
            NEW_DATA_SET_SENTINEL, address(listener), new Cids.Cid[](0), abi.encode(empty, empty)
        );
        assertEq(pdpVerifier.getDataSetLastProvenEpoch(setId), 0, "Initial lastProvenEpoch should be 0");

        // Mock block.number to 2881
        uint256 blockNumber = 2881;
        vm.roll(blockNumber);
        // Add a piece and verify lastProvenEpoch is set to current block number
        Cids.Cid[] memory pieces = new Cids.Cid[](1);
        pieces[0] = makeSamplePiece(2);

        pdpVerifier.addPieces(setId, address(0), pieces, empty);
        pdpVerifier.nextProvingPeriod(setId, blockNumber + CHALLENGE_FINALITY_DELAY, empty);
        assertEq(
            pdpVerifier.getDataSetLastProvenEpoch(setId),
            blockNumber,
            "lastProvenEpoch should be set to block.number after first proving period piece"
        );

        // Schedule piece removal
        uint256[] memory piecesToRemove = new uint256[](1);
        piecesToRemove[0] = 0;
        pdpVerifier.schedulePieceDeletions(setId, piecesToRemove, empty);

        // Call nextProvingPeriod and verify lastProvenEpoch is reset to 0
        pdpVerifier.nextProvingPeriod(setId, blockNumber + CHALLENGE_FINALITY_DELAY, empty);
        assertEq(
            pdpVerifier.getDataSetLastProvenEpoch(setId),
            0,
            "lastProvenEpoch should be reset to 0 after removing last piece"
        );
    }

    function testLateProofAccepted() public {
        uint256 leafCount = 10;
        (uint256 setId, bytes32[][] memory tree) = makeDataSetWithOnePiece(leafCount);

        // Advance chain short of challenge epoch
        uint256 challengeEpoch = pdpVerifier.getNextChallengeEpoch(setId);
        vm.roll(challengeEpoch + 100);

        // Build a proof.
        IPDPTypes.Proof[] memory proofs = buildProofsForSingleton(setId, 3, tree, leafCount);

        // Submit proof.
        RANDOMNESS_PRECOMPILE.mockBeaconRandomness(challengeEpoch, challengeEpoch);
        pdpVerifier.provePossession{value: 1e18}(setId, proofs);
    }

    function testProvePossesionSmall() public {
        uint256 leafCount = 3;
        (uint256 setId, bytes32[][] memory tree) = makeDataSetWithOnePiece(leafCount);

        // Advance chain short of challenge epoch
        uint256 challengeEpoch = pdpVerifier.getNextChallengeEpoch(setId);
        vm.roll(challengeEpoch);

        // Build a proof.
        IPDPTypes.Proof[] memory proofs = buildProofsForSingleton(setId, 3, tree, leafCount);

        // Submit proof.
        RANDOMNESS_PRECOMPILE.mockBeaconRandomness(challengeEpoch, challengeEpoch);
        pdpVerifier.provePossession{value: 1e18}(setId, proofs);
    }

    function testEarlyProofRejected() public {
        uint256 leafCount = 10;
        (uint256 setId, bytes32[][] memory tree) = makeDataSetWithOnePiece(leafCount);

        // Advance chain short of challenge epoch
        uint256 challengeEpoch = pdpVerifier.getNextChallengeEpoch(setId);
        vm.roll(challengeEpoch - 1);

        // Build a proof.
        IPDPTypes.Proof[] memory proofs = buildProofsForSingleton(setId, 3, tree, leafCount);

        // Submit proof.
        vm.expectRevert();
        pdpVerifier.provePossession{value: 1e18}(setId, proofs);
    }

    function testProvePossessionFailsWithNoScheduledChallenge() public {
        uint256 setId = pdpVerifier.addPieces{value: PDPFees.sybilFee()}(
            NEW_DATA_SET_SENTINEL, address(listener), new Cids.Cid[](0), abi.encode(empty, empty)
        );
        Cids.Cid[] memory pieces = new Cids.Cid[](1);
        pieces[0] = makeSamplePiece(2);
        pdpVerifier.addPieces(setId, address(0), pieces, empty);

        // Don't sample challenge (i.e. call nextProvingPeriod)

        // Create a dummy proof
        IPDPTypes.Proof[] memory proofs = new IPDPTypes.Proof[](1);
        proofs[0].leaf = bytes32(0);
        proofs[0].proof = new bytes32[](1);
        proofs[0].proof[0] = bytes32(0);

        // Try to prove possession without scheduling a challenge
        // This should fail because nextChallengeEpoch is still NO_CHALLENGE_SCHEDULED (0)
        vm.expectRevert("no challenge scheduled");
        pdpVerifier.provePossession{value: 1 ether}(setId, proofs);
    }

    function testEmptyProofRejected() public {
        uint256 setId = pdpVerifier.addPieces{value: PDPFees.sybilFee()}(
            NEW_DATA_SET_SENTINEL, address(listener), new Cids.Cid[](0), abi.encode(empty, empty)
        );
        IPDPTypes.Proof[] memory emptyProof = new IPDPTypes.Proof[](0);

        // Rejected with no pieces
        vm.expectRevert();
        pdpVerifier.provePossession{value: 1e18}(setId, emptyProof);

        addOnePiece(setId, 10);

        // Rejected with a piece
        vm.expectRevert();
        pdpVerifier.provePossession{value: 1e18}(setId, emptyProof);
    }

    function testBadChallengeRejected() public {
        uint256 leafCount = 10;
        (uint256 setId, bytes32[][] memory tree) = makeDataSetWithOnePiece(leafCount);

        // Make a proof that's good for this challenge epoch.
        uint256 challengeEpoch = pdpVerifier.getNextChallengeEpoch(setId);
        vm.roll(challengeEpoch);
        IPDPTypes.Proof[] memory proofs = buildProofsForSingleton(setId, 3, tree, leafCount);

        // Submit proof successfully, advancing the data set to a new challenge epoch.
        RANDOMNESS_PRECOMPILE.mockBeaconRandomness(challengeEpoch, challengeEpoch);

        pdpVerifier.provePossession{value: 1e18}(setId, proofs);
        pdpVerifier.nextProvingPeriod(setId, vm.getBlockNumber() + CHALLENGE_FINALITY_DELAY, empty); // resample

        uint256 nextChallengeEpoch = pdpVerifier.getNextChallengeEpoch(setId);
        assertNotEq(nextChallengeEpoch, challengeEpoch);
        vm.roll(nextChallengeEpoch);

        // The proof for the old challenge epoch should no longer be valid.
        vm.expectRevert();
        pdpVerifier.provePossession{value: 1e18}(setId, proofs);
    }

    function testBadPiecesRejected() public {
        uint256[] memory leafCounts = new uint256[](2);
        // Note: either co-prime leaf counts or a challenge count > 1 are required for this test to demonstrate the failing proof.
        // With a challenge count == 1 and leaf counts e.g. 10 and 20 it just so happens that the first computed challenge index is the same
        // (lying in the first piece) whether the tree has one or two pieces.
        // This could be prevented if the challenge index calculation included some marker of data set contents, like
        // a hash of all the pieces or an edit sequence number.
        leafCounts[0] = 7;
        leafCounts[1] = 13;
        bytes32[][][] memory trees = new bytes32[][][](2);
        // Make data set initially with one piece.
        (uint256 setId, bytes32[][] memory tree) = makeDataSetWithOnePiece(leafCounts[0]);
        trees[0] = tree;
        // Add another piece before submitting the proof.
        uint256 newPieceId;
        (trees[1], newPieceId) = addOnePiece(setId, leafCounts[1]);

        // Make a proof that's good for the single piece.
        uint256 challengeEpoch = pdpVerifier.getNextChallengeEpoch(setId);
        vm.roll(challengeEpoch);
        IPDPTypes.Proof[] memory proofsOneRoot = buildProofsForSingleton(setId, 3, trees[0], leafCounts[0]);

        // The proof for one piece should be invalid against the set with two.
        RANDOMNESS_PRECOMPILE.mockBeaconRandomness(challengeEpoch, challengeEpoch);
        vm.expectRevert();
        pdpVerifier.provePossession{value: 1e18}(setId, proofsOneRoot);

        // Remove a piece and resample
        uint256[] memory removePieces = new uint256[](1);
        removePieces[0] = newPieceId;
        pdpVerifier.schedulePieceDeletions(setId, removePieces, empty);
        // flush removes
        pdpVerifier.nextProvingPeriod(setId, vm.getBlockNumber() + CHALLENGE_FINALITY_DELAY, empty);

        // Make a new proof that is valid with two pieces
        challengeEpoch = pdpVerifier.getNextChallengeEpoch(setId);
        vm.roll(challengeEpoch);
        IPDPTypes.Proof[] memory proofsTwoRoots = buildProofs(pdpVerifier, setId, 10, trees, leafCounts);

        // A proof for two pieces should be invalid against the set with one.
        proofsTwoRoots = buildProofs(pdpVerifier, setId, 10, trees, leafCounts); // regen as removal forced resampling challenge seed
        RANDOMNESS_PRECOMPILE.mockBeaconRandomness(challengeEpoch, challengeEpoch);
        vm.expectRevert();
        pdpVerifier.provePossession{value: 1e18}(setId, proofsTwoRoots);

        // But the single piece proof is now good again.
        proofsOneRoot = buildProofsForSingleton(setId, 1, trees[0], leafCounts[0]); // regen as removal forced resampling challenge seed
        RANDOMNESS_PRECOMPILE.mockBeaconRandomness(challengeEpoch, challengeEpoch);
        pdpVerifier.provePossession{value: 1e18}(setId, proofsOneRoot);
    }

    function testProveManyPieces() public {
        uint256[] memory leafCounts = new uint256[](3);
        // Pick a distinct size for each tree (up to some small maximum size).
        for (uint256 i = 0; i < leafCounts.length; i++) {
            leafCounts[i] = uint256(sha256(abi.encode(i))) % 64;
        }

        (uint256 setId, bytes32[][][] memory trees) = makeDataSetWithPieces(leafCounts);

        // Advance chain until challenge epoch.
        uint256 challengeEpoch = pdpVerifier.getNextChallengeEpoch(setId);
        vm.roll(challengeEpoch);

        // Build a proof with multiple challenges to span the pieces.
        uint256 challengeCount = 11;
        IPDPTypes.Proof[] memory proofs = buildProofs(pdpVerifier, setId, challengeCount, trees, leafCounts);
        // Submit proof.
        RANDOMNESS_PRECOMPILE.mockBeaconRandomness(challengeEpoch, challengeEpoch);
        pdpVerifier.provePossession{value: 1e18}(setId, proofs);
    }

    function testNextProvingPeriodFlexibleScheduling() public {
        // Create data set and add initial piece
        uint256 leafCount = 10;
        (uint256 setId, bytes32[][] memory tree) = makeDataSetWithOnePiece(leafCount);

        // Set challenge sampling far in the future
        uint256 farFutureBlock = vm.getBlockNumber() + 1000;
        pdpVerifier.nextProvingPeriod(setId, farFutureBlock, empty);
        assertEq(
            pdpVerifier.getNextChallengeEpoch(setId), farFutureBlock, "Challenge epoch should be set to far future"
        );

        // Reset to a closer block
        uint256 nearerBlock = vm.getBlockNumber() + CHALLENGE_FINALITY_DELAY;
        pdpVerifier.nextProvingPeriod(setId, nearerBlock, empty);
        assertEq(
            pdpVerifier.getNextChallengeEpoch(setId), nearerBlock, "Challenge epoch should be reset to nearer block"
        );

        // Verify we can still prove possession at the new block
        vm.roll(nearerBlock);

        IPDPTypes.Proof[] memory proofs = buildProofsForSingleton(setId, 5, tree, 10);
        RANDOMNESS_PRECOMPILE.mockBeaconRandomness(
            pdpVerifier.getNextChallengeEpoch(setId), pdpVerifier.getNextChallengeEpoch(setId)
        );
        pdpVerifier.provePossession{value: 1e18}(setId, proofs);
    }

    function testProveSingleFake() public {
        uint256 leafCount = 10;
        (uint256 setId, bytes32[][] memory tree) = makeDataSetWithOnePiece(leafCount);

        // Advance chain until challenge epoch.
        uint256 challengeEpoch = pdpVerifier.getNextChallengeEpoch(setId);
        vm.roll(challengeEpoch);

        uint256 challengeCount = 3;
        // build fake proofs
        IPDPTypes.Proof[] memory proofs = new IPDPTypes.Proof[](5);
        for (uint256 i = 0; i < 5; i++) {
            proofs[i] = IPDPTypes.Proof(tree[0][0], new bytes32[](0));
        }

        // Submit proof.
        RANDOMNESS_PRECOMPILE.mockBeaconRandomness(challengeEpoch, challengeEpoch);
        IPDPTypes.PieceIdAndOffset[] memory challenges = new IPDPTypes.PieceIdAndOffset[](challengeCount);
        for (uint256 i = 0; i < challengeCount; i++) {
            challenges[i] = IPDPTypes.PieceIdAndOffset(0, 0);
        }
        vm.expectRevert("proof length does not match tree height");
        pdpVerifier.provePossession{value: 1e18}(setId, proofs);
    }

    ///// Helpers /////

    // Initializes a new data set, generates trees of specified sizes, and adds pieces to the set.
    function makeDataSetWithPieces(uint256[] memory leafCounts) internal returns (uint256, bytes32[][][] memory) {
        // Create trees and their pieces.
        bytes32[][][] memory trees = new bytes32[][][](leafCounts.length);
        Cids.Cid[] memory pieces = new Cids.Cid[](leafCounts.length);
        for (uint256 i = 0; i < leafCounts.length; i++) {
            // Generate a uniquely-sized tree for each piece (up to some small maximum size).
            if (leafCounts[i] < 4) {
                trees[i] = ProofUtil.makeTree(4);
                pieces[i] = makePieceBytes(trees[i], leafCounts[i] * 32);
            } else {
                trees[i] = ProofUtil.makeTree(leafCounts[i]);
                pieces[i] = makePiece(trees[i], leafCounts[i]);
            }
        }

        // Create new data set and add pieces.
        uint256 setId = pdpVerifier.addPieces{value: PDPFees.sybilFee()}(
            NEW_DATA_SET_SENTINEL, address(listener), new Cids.Cid[](0), abi.encode(empty, empty)
        );
        pdpVerifier.addPieces(setId, address(0), pieces, empty);
        pdpVerifier.nextProvingPeriod(setId, vm.getBlockNumber() + CHALLENGE_FINALITY_DELAY, empty); // flush adds
        return (setId, trees);
    }

    // Initializes a new data set and adds a single generated tree.
    function makeDataSetWithOnePiece(uint256 leafCount) internal returns (uint256, bytes32[][] memory) {
        uint256[] memory leafCounts = new uint256[](1);
        leafCounts[0] = leafCount;
        (uint256 setId, bytes32[][][] memory trees) = makeDataSetWithPieces(leafCounts);
        return (setId, trees[0]);
    }

    // Creates a tree and adds it to a data set.
    // Returns the Merkle tree and piece.
    function addOnePiece(uint256 setId, uint256 leafCount) internal returns (bytes32[][] memory, uint256) {
        bytes32[][] memory tree = ProofUtil.makeTree(leafCount);
        Cids.Cid[] memory pieces = new Cids.Cid[](1);
        pieces[0] = makePiece(tree, leafCount);
        uint256 pieceId = pdpVerifier.addPieces(setId, address(0), pieces, empty);
        pdpVerifier.nextProvingPeriod(setId, vm.getBlockNumber() + CHALLENGE_FINALITY_DELAY, empty); // flush adds
        return (tree, pieceId);
    }

    // Builds a proof of posesesion for a data set with a single piece.
    function buildProofsForSingleton(uint256 setId, uint256 challengeCount, bytes32[][] memory tree, uint256 leafCount)
        internal
        view
        returns (IPDPTypes.Proof[] memory)
    {
        bytes32[][][] memory trees = new bytes32[][][](1);
        trees[0] = tree;
        uint256[] memory leafCounts = new uint256[](1);
        leafCounts[0] = leafCount;
        IPDPTypes.Proof[] memory proofs = buildProofs(pdpVerifier, setId, challengeCount, trees, leafCounts);
        return proofs;
    }
}
