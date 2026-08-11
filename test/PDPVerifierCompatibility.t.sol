// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.20;

import {MockFVMTest} from "fvm-solidity/mocks/MockFVMTest.sol";
import {Cids} from "../src/Cids.sol";
import {PDPVerifier} from "../src/PDPVerifier.sol";
import {MyERC1967Proxy} from "../src/ERC1967Proxy.sol";
import {PDPFees} from "../src/Fees.sol";
import {ProofUtil} from "./ProofUtil.sol";
import {PieceHelper} from "./PieceHelper.t.sol";
import {ProofBuilderHelper} from "./ProofBuilderHelper.t.sol";
import {IPDPTypes} from "../src/interfaces/IPDPTypes.sol";
import {COMPACT_PIECES_SLOT, NEXT_PIECE_ID_SLOT, STORAGE_PROVIDER_SLOT} from "../src/PDPVerifierLayout.sol";

contract LegacyModePDPVerifier is PDPVerifier {
    constructor(uint64 initializerVersion, uint256 challengeFinality)
        PDPVerifier(initializerVersion, challengeFinality)
    {}

    function useLegacyPieceStorageForTest() external {
        legacyPieceStorageIdLimit = 0;
    }
}

contract PDPVerifierCompatibilityTest is MockFVMTest, PieceHelper, ProofBuilderHelper {
    uint256 private constant CHALLENGE_FINALITY_DELAY = 2;

    LegacyModePDPVerifier private legacyImplementation;
    MyERC1967Proxy private proxy;
    PDPVerifier private verifier;

    function setUp() public override {
        super.setUp();
        legacyImplementation = new LegacyModePDPVerifier(1, CHALLENGE_FINALITY_DELAY);
        proxy =
            new MyERC1967Proxy(address(legacyImplementation), abi.encodeWithSelector(PDPVerifier.initialize.selector));
        verifier = PDPVerifier(address(proxy));
        LegacyModePDPVerifier(address(proxy)).useLegacyPieceStorageForTest();
        assertEq(verifier.legacyPieceStorageIdLimit(), 0);
    }

    function testFreshDeploymentStartsCompactAtDataSetOne() public {
        PDPVerifier freshImplementation = new PDPVerifier(1, CHALLENGE_FINALITY_DELAY);
        PDPVerifier fresh = PDPVerifier(
            address(
                new MyERC1967Proxy(
                    address(freshImplementation), abi.encodeWithSelector(PDPVerifier.initialize.selector)
                )
            )
        );

        assertEq(fresh.legacyPieceStorageIdLimit(), 1);
        uint256 setId = fresh.createDataSet{value: PDPFees.cleanupDeposit()}(address(0), "");
        assertEq(setId, 1);
        fresh.addPieces(setId, address(0), _samplePieces(), "");
        assertEq(uint256(vm.load(address(fresh), keccak256(abi.encode(setId, uint256(NEXT_PIECE_ID_SLOT))))), 0);
        assertEq(uint256(vm.load(address(fresh), keccak256(abi.encode(setId, uint256(COMPACT_PIECES_SLOT))))), 3);
    }

    function testMigrationWithoutExistingDataSetsStartsCompactAtOne() public {
        _upgradeAndMigrate(2);
        assertEq(verifier.legacyPieceStorageIdLimit(), 1);
        uint256 compactSetId = _createDataSetWithPieces(_samplePieces());
        assertEq(compactSetId, 1);
        assertEq(_legacyPieceCount(compactSetId), 0);
        assertEq(_compactPieceCount(compactSetId), 3);
    }

    function testMigrationCreatesPermanentExclusiveBoundary() public {
        uint256 legacySetId = _createDataSetWithPieces(_samplePieces());
        uint64 boundary = verifier.getNextDataSetId();
        assertEq(_legacyPieceCount(legacySetId), 3);
        assertEq(_compactPieceCount(legacySetId), 0);

        _upgradeAndMigrate(2);
        assertEq(verifier.legacyPieceStorageIdLimit(), boundary);
        assertEq(verifier.getNextPieceId(legacySetId), 3);

        Cids.Cid[] memory appended = new Cids.Cid[](1);
        appended[0] = makeSamplePiece(4);
        assertEq(verifier.addPieces(legacySetId, address(0), appended, ""), 3);
        assertEq(_legacyPieceCount(legacySetId), 4);
        assertEq(_compactPieceCount(legacySetId), 0);

        uint256 compactSetId = _createDataSetWithPieces(_samplePieces());
        assertEq(compactSetId, boundary);
        assertEq(_legacyPieceCount(compactSetId), 0);
        assertEq(_compactPieceCount(compactSetId), 3);

        _upgradeAndMigrate(3);
        assertEq(verifier.legacyPieceStorageIdLimit(), boundary, "future migration moved boundary");
        assertEq(verifier.getNextPieceId(legacySetId), 4);
        assertEq(verifier.getNextPieceId(compactSetId), 3);
    }

    function testDelayedMigrationKeepsInterimDataSetsLegacy() public {
        uint256 firstLegacySetId = _createDataSetWithPieces(_samplePieces());
        _upgradeWithoutMigration(2);
        assertEq(verifier.legacyPieceStorageIdLimit(), 0);

        uint256 interimLegacySetId = _createDataSetWithPieces(_samplePieces());
        assertEq(_legacyPieceCount(firstLegacySetId), 3);
        assertEq(_legacyPieceCount(interimLegacySetId), 3);
        assertEq(_compactPieceCount(interimLegacySetId), 0);

        uint64 boundary = verifier.getNextDataSetId();
        verifier.migrate();
        assertEq(verifier.legacyPieceStorageIdLimit(), boundary);

        uint256 compactSetId = _createDataSetWithPieces(_samplePieces());
        assertEq(compactSetId, boundary);
        assertEq(_legacyPieceCount(compactSetId), 0);
        assertEq(_compactPieceCount(compactSetId), 3);
    }

    function testEquivalentQueriesRemovalAppendAndCleanup() public {
        Cids.Cid[] memory pieces = _samplePieces();
        uint256 legacySetId = _createDataSetWithPieces(pieces);
        _upgradeAndMigrate(2);
        uint256 compactSetId = _createDataSetWithPieces(pieces);

        _assertEquivalentQueries(legacySetId, compactSetId, pieces);

        uint256[] memory removals = new uint256[](1);
        removals[0] = 1;
        verifier.schedulePieceDeletions(legacySetId, removals, "");
        verifier.schedulePieceDeletions(compactSetId, removals, "");
        verifier.processPieceDeletions(legacySetId, removals.length);
        verifier.processPieceDeletions(compactSetId, removals.length);
        verifier.nextProvingPeriod(legacySetId, block.number + CHALLENGE_FINALITY_DELAY, "");
        verifier.nextProvingPeriod(compactSetId, block.number + CHALLENGE_FINALITY_DELAY, "");

        assertFalse(verifier.pieceLive(legacySetId, 1));
        assertFalse(verifier.pieceLive(compactSetId, 1));
        assertEq(verifier.getDataSetLeafCount(legacySetId), verifier.getDataSetLeafCount(compactSetId));
        assertTrue(verifier.pieceChallengable(legacySetId, 0));
        assertTrue(verifier.pieceChallengable(compactSetId, 0));
        assertFalse(verifier.pieceChallengable(legacySetId, 1));
        assertFalse(verifier.pieceChallengable(compactSetId, 1));
        assertTrue(verifier.pieceChallengable(legacySetId, 2));
        assertTrue(verifier.pieceChallengable(compactSetId, 2));

        uint256[] memory leafIndexes = new uint256[](4);
        leafIndexes[0] = 0;
        leafIndexes[1] = 1;
        leafIndexes[2] = 2;
        leafIndexes[3] = 3;
        IPDPTypes.PieceIdAndOffset[] memory legacyLocations = verifier.findPieceIds(legacySetId, leafIndexes);
        IPDPTypes.PieceIdAndOffset[] memory compactLocations = verifier.findPieceIds(compactSetId, leafIndexes);
        for (uint256 i = 0; i < leafIndexes.length; i++) {
            assertEq(legacyLocations[i].pieceId, compactLocations[i].pieceId);
            assertEq(legacyLocations[i].offset, compactLocations[i].offset);
        }

        Cids.Cid[] memory appended = new Cids.Cid[](1);
        appended[0] = makeSamplePiece(4);
        assertEq(verifier.addPieces(legacySetId, address(0), appended, ""), 3);
        assertEq(verifier.addPieces(compactSetId, address(0), appended, ""), 3);
        assertEq(_legacyPieceCount(legacySetId), 4);
        assertEq(_compactPieceCount(compactSetId), 4);

        verifier.deleteDataSet(legacySetId, "");
        verifier.deleteDataSet(compactSetId, "");
        assertFalse(verifier.cleanupPieces(legacySetId, 2));
        assertFalse(verifier.cleanupPieces(compactSetId, 2));
        assertEq(verifier.getNextPieceId(legacySetId), 2);
        assertEq(verifier.getNextPieceId(compactSetId), 2);
        assertTrue(verifier.cleanupPieces(legacySetId, 2));
        assertTrue(verifier.cleanupPieces(compactSetId, 2));
        assertEq(_legacyPieceCount(legacySetId), 0);
        assertEq(_compactPieceCount(compactSetId), 0);
    }

    function testLegacyPartialDeletionPreservesPendingRemovalMarkerInSameBitmapSlot() public {
        uint256 legacySetId = _createDataSetWithPieces(_samplePieces());
        uint64 boundary = verifier.getNextDataSetId();
        _upgradeAndMigrate(2);

        assertEq(verifier.legacyPieceStorageIdLimit(), boundary);
        assertTrue(legacySetId < boundary);
        assertEq(_legacyPieceCount(legacySetId), 3);
        assertEq(_compactPieceCount(legacySetId), 0);

        uint256[] memory scheduled = new uint256[](3);
        scheduled[0] = 0;
        scheduled[1] = 1;
        scheduled[2] = 2;
        verifier.schedulePieceDeletions(legacySetId, scheduled, "");

        uint256[] memory suffix = new uint256[](2);
        suffix[0] = 1;
        suffix[1] = 2;
        verifier.processPieceDeletions(legacySetId, suffix.length);

        uint256[] memory pending = new uint256[](1);
        pending[0] = 0;
        assertEq(verifier.getScheduledRemovals(legacySetId), pending);
        assertTrue(verifier.pieceLive(legacySetId, 0));
        assertFalse(verifier.pieceLive(legacySetId, 1));
        assertFalse(verifier.pieceLive(legacySetId, 2));

        vm.expectRevert("Piece ID already scheduled for removal");
        verifier.schedulePieceDeletions(legacySetId, pending, "");
        assertEq(verifier.getScheduledRemovals(legacySetId), pending);
    }

    function testPossessionProofWorksForBothRepresentations() public {
        uint256 leafCount = 4;
        bytes32[][] memory tree = ProofUtil.makeTree(leafCount);
        Cids.Cid[] memory pieces = new Cids.Cid[](1);
        pieces[0] = makePiece(tree, leafCount);

        uint256 legacySetId = _createDataSetWithPieces(pieces);
        _upgradeAndMigrate(2);
        uint256 compactSetId = _createDataSetWithPieces(pieces);

        uint256 challengeEpoch = block.number + CHALLENGE_FINALITY_DELAY;
        verifier.nextProvingPeriod(legacySetId, challengeEpoch, "");
        verifier.nextProvingPeriod(compactSetId, challengeEpoch, "");
        RANDOMNESS_PRECOMPILE.mockBeaconRandomness(challengeEpoch, challengeEpoch);

        bytes32[][][] memory trees = new bytes32[][][](1);
        trees[0] = tree;
        uint256[] memory leafCounts = new uint256[](1);
        leafCounts[0] = leafCount;
        IPDPTypes.Proof[] memory legacyProofs = buildProofs(verifier, legacySetId, 2, trees, leafCounts);
        IPDPTypes.Proof[] memory compactProofs = buildProofs(verifier, compactSetId, 2, trees, leafCounts);

        vm.roll(challengeEpoch);
        verifier.provePossession{value: 1 ether}(legacySetId, legacyProofs);
        verifier.provePossession{value: 1 ether}(compactSetId, compactProofs);
        assertEq(verifier.getDataSetLastProvenEpoch(legacySetId), challengeEpoch);
        assertEq(verifier.getDataSetLastProvenEpoch(compactSetId), challengeEpoch);
    }

    function testHistoricalDeletedLegacyDataSetRemainsCleanable() public {
        uint256 legacySetId = _createDataSetWithPieces(_samplePieces());
        _upgradeAndMigrate(2);

        vm.store(address(verifier), keccak256(abi.encode(legacySetId, uint256(STORAGE_PROVIDER_SLOT))), bytes32(0));

        address cleaner = address(0xCAFE);
        vm.deal(cleaner, 1 ether);
        vm.prank(cleaner);
        assertTrue(verifier.cleanupPieces(legacySetId, 10));
        assertEq(_legacyPieceCount(legacySetId), 0);
    }

    function testCompactDataSetCannotUseHistoricalCleanupPath() public {
        _createDataSetWithPieces(_samplePieces());
        _upgradeAndMigrate(2);
        uint256 compactSetId = _createDataSetWithPieces(_samplePieces());

        vm.store(address(verifier), keccak256(abi.encode(compactSetId, uint256(STORAGE_PROVIDER_SLOT))), bytes32(0));

        vm.expectRevert(PDPVerifier.DataSetNotInCleanupMode.selector);
        verifier.cleanupPieces(compactSetId, 10);
    }

    function _assertEquivalentQueries(uint256 legacySetId, uint256 compactSetId, Cids.Cid[] memory pieces)
        private
        view
    {
        assertEq(verifier.getNextPieceId(legacySetId), verifier.getNextPieceId(compactSetId));
        assertEq(verifier.getActivePieceCount(legacySetId), verifier.getActivePieceCount(compactSetId));
        for (uint256 i = 0; i < pieces.length; i++) {
            assertEq(verifier.getPieceCid(legacySetId, i).data, verifier.getPieceCid(compactSetId, i).data);
            assertEq(verifier.getPieceLeafCount(legacySetId, i), verifier.getPieceLeafCount(compactSetId, i));
            assertEq(verifier.pieceLive(legacySetId, i), verifier.pieceLive(compactSetId, i));
        }

        (Cids.Cid[] memory legacyPieces, uint256[] memory legacyIds, bool legacyHasMore) =
            verifier.getActivePiecesByCursor(legacySetId, 0, 2);
        (Cids.Cid[] memory compactPieces, uint256[] memory compactIds, bool compactHasMore) =
            verifier.getActivePiecesByCursor(compactSetId, 0, 2);
        assertEq(legacyPieces.length, compactPieces.length);
        assertEq(legacyIds, compactIds);
        assertEq(legacyHasMore, compactHasMore);
        for (uint256 i = 0; i < legacyPieces.length; i++) {
            assertEq(legacyPieces[i].data, compactPieces[i].data);
        }

        (legacyPieces, legacyIds, legacyHasMore) = verifier.getActivePieces(legacySetId, 1, 1);
        (compactPieces, compactIds, compactHasMore) = verifier.getActivePieces(compactSetId, 1, 1);
        assertEq(legacyPieces.length, compactPieces.length);
        assertEq(legacyIds, compactIds);
        assertEq(legacyHasMore, compactHasMore);
        assertEq(legacyPieces[0].data, compactPieces[0].data);
        uint256[] memory legacyMatches = verifier.findPieceIdsByCid(legacySetId, pieces[0], 0, 10);
        uint256[] memory compactMatches = verifier.findPieceIdsByCid(compactSetId, pieces[0], 0, 10);
        assertEq(legacyMatches, compactMatches);
    }

    function _samplePieces() private pure returns (Cids.Cid[] memory pieces) {
        pieces = new Cids.Cid[](3);
        pieces[0] = makeSamplePiece(2);
        pieces[1] = makeSamplePiece(3);
        pieces[2] = makeSamplePiece(2);
    }

    function _createDataSetWithPieces(Cids.Cid[] memory pieces) private returns (uint256 setId) {
        setId = verifier.createDataSet{value: PDPFees.cleanupDeposit()}(address(0), "");
        verifier.addPieces(setId, address(0), pieces, "");
    }

    function _upgradeAndMigrate(uint64 initializerVersion) private {
        PDPVerifier nextImplementation = new PDPVerifier(initializerVersion, CHALLENGE_FINALITY_DELAY);
        verifier.announceUpgradePlan(address(nextImplementation), 1);
        vm.roll(block.number + 1);
        verifier.upgradeToAndCall(address(nextImplementation), abi.encodeWithSelector(PDPVerifier.migrate.selector));
    }

    function _upgradeWithoutMigration(uint64 initializerVersion) private {
        PDPVerifier nextImplementation = new PDPVerifier(initializerVersion, CHALLENGE_FINALITY_DELAY);
        verifier.announceUpgradePlan(address(nextImplementation), 1);
        vm.roll(block.number + 1);
        verifier.upgradeToAndCall(address(nextImplementation), "");
    }

    function _legacyPieceCount(uint256 setId) private view returns (uint256) {
        return uint256(vm.load(address(verifier), keccak256(abi.encode(setId, uint256(NEXT_PIECE_ID_SLOT)))));
    }

    function _compactPieceCount(uint256 setId) private view returns (uint256) {
        return uint256(vm.load(address(verifier), keccak256(abi.encode(setId, uint256(COMPACT_PIECES_SLOT)))));
    }
}
