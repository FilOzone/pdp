// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.13;

import {MockFVMTest} from "fvm-solidity/mocks/MockFVMTest.sol";
import {Cids} from "../src/Cids.sol";
import {PDPVerifier, PDPListener} from "../src/PDPVerifier.sol";
import {MyERC1967Proxy} from "../src/ERC1967Proxy.sol";
import {PDPFees} from "../src/Fees.sol";
import {PDPRecordKeeper} from "../src/SimplePDPService.sol";
import {PieceHelper} from "./PieceHelper.t.sol";
import {NEW_DATA_SET_SENTINEL} from "../src/PDPVerifier.sol";
import {
    DATA_SET_LAST_PROVEN_EPOCH_SLOT,
    DEPRECATED_CLEANUP_MODE_EPOCH_SLOT,
    PIECE_CIDS_SLOT,
    PIECE_LEAF_COUNTS_SLOT,
    STORAGE_PROVIDER_SLOT,
    SUM_TREE_COUNTS_SLOT
} from "../src/PDPVerifierLayout.sol";

contract TestListener is PDPListener, PDPRecordKeeper {
    function storageProviderChanged(uint256, address, address, bytes calldata) external override {}

    function dataSetCreated(uint256 dataSetId, address creator, bytes calldata extraData) external override {
        receiveDataSetEvent(dataSetId, PDPRecordKeeper.OperationType.CREATE, abi.encode(creator, extraData));
    }

    function dataSetDeleted(uint256 dataSetId, uint256 deletedLeafCount, bytes calldata) external override {
        receiveDataSetEvent(dataSetId, PDPRecordKeeper.OperationType.DELETE, abi.encode(deletedLeafCount));
    }

    function piecesAdded(uint256 dataSetId, uint256 firstAdded, Cids.Cid[] calldata pieceData, bytes calldata)
        external
        override
    {
        receiveDataSetEvent(dataSetId, PDPRecordKeeper.OperationType.ADD, abi.encode(firstAdded, pieceData));
    }

    function piecesScheduledRemove(uint256 dataSetId, uint256[] calldata pieceIds, bytes calldata) external override {
        receiveDataSetEvent(dataSetId, PDPRecordKeeper.OperationType.REMOVE_SCHEDULED, abi.encode(pieceIds));
    }

    function possessionProven(uint256 dataSetId, uint256 challengedLeafCount, uint256 seed, uint256 challengeCount)
        external
        override
    {
        receiveDataSetEvent(
            dataSetId,
            PDPRecordKeeper.OperationType.PROVE_POSSESSION,
            abi.encode(challengedLeafCount, seed, challengeCount)
        );
    }

    function nextProvingPeriod(uint256 dataSetId, uint256 challengeEpoch, uint256 leafCount, bytes calldata)
        external
        override
    {
        receiveDataSetEvent(
            dataSetId, PDPRecordKeeper.OperationType.NEXT_PROVING_PERIOD, abi.encode(challengeEpoch, leafCount)
        );
    }
}

contract PDPVerifierCleanupTest is MockFVMTest, PieceHelper {
    uint256 constant CHALLENGE_FINALITY_DELAY = 2;

    PDPVerifier pdpVerifier;
    TestListener listener;
    bytes empty = new bytes(0);

    function setUp() public override {
        super.setUp();
        PDPVerifier pdpVerifierImpl = new PDPVerifier(1, CHALLENGE_FINALITY_DELAY);
        bytes memory initializeData = abi.encodeWithSelector(PDPVerifier.initialize.selector);
        MyERC1967Proxy proxy = new MyERC1967Proxy(address(pdpVerifierImpl), initializeData);
        pdpVerifier = PDPVerifier(address(proxy));
        listener = new TestListener();
    }

    function _createAndPopulate(uint256 numPieces) internal returns (uint256 setId) {
        setId = pdpVerifier.addPieces{value: PDPFees.cleanupDeposit()}(
            NEW_DATA_SET_SENTINEL, address(listener), new Cids.Cid[](0), abi.encode(empty, empty)
        );
        if (numPieces > 0) {
            Cids.Cid[] memory pieces = new Cids.Cid[](numPieces);
            for (uint256 i = 0; i < numPieces; i++) {
                pieces[i] = makeSamplePiece(2);
            }
            pdpVerifier.addPieces(setId, address(0), pieces, empty);
        }
    }

    // Asserts that pieceCids, pieceLeafCounts, and sumTreeCounts are all zero for
    // every piece slot [0, numPieces) on the given data set.  Reads raw storage via
    // vm.load so that the check works even after the data set is no longer live.
    function assertPieceSlotsCleared(uint256 setId, uint256 numPieces) internal view {
        // Inner mapping root keyed by setId — shared across all pieces.
        bytes32 cidRoot = keccak256(abi.encode(setId, PIECE_CIDS_SLOT));
        bytes32 leafRoot = keccak256(abi.encode(setId, PIECE_LEAF_COUNTS_SLOT));
        bytes32 sumRoot = keccak256(abi.encode(setId, SUM_TREE_COUNTS_SLOT));

        for (uint256 pieceId = 0; pieceId < numPieces; pieceId++) {
            // pieceCids stores a `bytes` value; for a 39-byte CID the header holds length*2+1=79.
            // After delete, the header must be zero.
            bytes32 cidHeaderSlot = keccak256(abi.encode(pieceId, cidRoot));
            assertEq(vm.load(address(pdpVerifier), cidHeaderSlot), bytes32(0), "pieceCids header not cleared");
            // For a 39-byte CID (long encoding), the payload occupies 2 slots at keccak256(headerSlot).
            // ceil(39/32) = 2, so both data slots must be zero for storage to be fully reclaimed.
            bytes32 cidDataSlot = keccak256(abi.encodePacked(cidHeaderSlot));
            assertEq(vm.load(address(pdpVerifier), cidDataSlot), bytes32(0), "pieceCids data slot 0 not cleared");
            assertEq(
                vm.load(address(pdpVerifier), bytes32(uint256(cidDataSlot) + 1)),
                bytes32(0),
                "pieceCids data slot 1 not cleared"
            );
            assertEq(
                vm.load(address(pdpVerifier), keccak256(abi.encode(pieceId, leafRoot))),
                bytes32(0),
                "pieceLeafCounts not cleared"
            );
            assertEq(
                vm.load(address(pdpVerifier), keccak256(abi.encode(pieceId, sumRoot))),
                bytes32(0),
                "sumTreeCounts not cleared"
            );
        }
    }

    // --- cleanupPieces basics ---

    function testCleanupPiecesIncrementalBatches() public {
        uint256 setId = _createAndPopulate(3);
        pdpVerifier.deleteDataSet(setId, empty);
        assertFalse(pdpVerifier.dataSetLive(setId));

        // clean 2 of 3
        bool done = pdpVerifier.cleanupPieces(setId, 2);
        assertFalse(done, "should not be done after 2 of 3");

        // clean last piece
        uint256 balanceBefore = address(this).balance;
        done = pdpVerifier.cleanupPieces(setId, 1);
        assertTrue(done, "should be done after last piece");
        assertEq(address(this).balance - balanceBefore, PDPFees.cleanupDeposit(), "deposit returned on completion");
        assertPieceSlotsCleared(setId, 3);
    }

    function testCleanupPiecesInOneCall() public {
        uint256 setId = _createAndPopulate(2);
        pdpVerifier.deleteDataSet(setId, empty);

        uint256 balanceBefore = address(this).balance;
        bool done = pdpVerifier.cleanupPieces(setId, 100);
        assertTrue(done);
        assertEq(address(this).balance - balanceBefore, PDPFees.cleanupDeposit());
        assertPieceSlotsCleared(setId, 2);
    }

    function testCleanupPiecesDepositNotPaidUntilComplete() public {
        uint256 setId = _createAndPopulate(3);
        pdpVerifier.deleteDataSet(setId, empty);

        uint256 balanceBefore = address(this).balance;
        pdpVerifier.cleanupPieces(setId, 2);
        assertEq(address(this).balance, balanceBefore, "no deposit paid for partial cleanup");
    }

    // --- zero-piece data sets ---

    function testZeroPieceDataSetFinalizesAtDelete() public {
        uint256 balanceBefore = address(this).balance;
        uint256 setId = _createAndPopulate(0); // holds cleanupDeposit

        pdpVerifier.deleteDataSet(setId, empty); // returns cleanupDeposit immediately

        // Net cost is zero; the cleanup deposit was returned at delete time
        assertEq(balanceBefore, address(this).balance, "net cost is zero");
        assertEq(address(pdpVerifier).balance, 0, "Verifier balance is 0 after deposit returned");
        assertFalse(pdpVerifier.dataSetLive(setId));
    }

    function testZeroPieceDataSetCleanupPiecesReverts() public {
        uint256 setId = _createAndPopulate(0);
        pdpVerifier.deleteDataSet(setId, empty);

        // After full finalization, cleanupPieces should revert
        vm.expectRevert(PDPVerifier.DataSetNotInCleanupMode.selector);
        pdpVerifier.cleanupPieces(setId, 10);
    }

    // --- caller gating ---

    function testOnlySpCanCleanWithinInactivityWindow() public {
        uint256 setId = _createAndPopulate(1);
        pdpVerifier.deleteDataSet(setId, empty);

        // block.number (1) <= lastProvenEpoch + INACTIVITY_WINDOW, so only SP can call
        address notSp = address(0xBEEF);
        vm.prank(notSp);
        vm.expectRevert(PDPVerifier.OnlyStorageProviderCanCleanupPieces.selector);
        pdpVerifier.cleanupPieces(setId, 10);

        // SP succeeds
        uint256 balanceBefore = address(this).balance;
        bool done = pdpVerifier.cleanupPieces(setId, 10);
        assertTrue(done);
        assertEq(address(this).balance - balanceBefore, PDPFees.cleanupDeposit(), "SP receives deposit");
        assertEq(address(pdpVerifier).balance, 0, "Verifier balance is 0 after cleanup");
        assertPieceSlotsCleared(setId, 1);
    }

    function testCleanupPermissionlessAfterInactivityWindow() public {
        uint256 setId = _createAndPopulate(1);
        pdpVerifier.deleteDataSet(setId, empty);

        vm.roll(block.number + pdpVerifier.INACTIVITY_WINDOW() + 1);

        address anyone = address(0xCAFE);
        vm.deal(anyone, 10 ether);
        uint256 balanceBefore = anyone.balance;

        vm.prank(anyone);
        bool done = pdpVerifier.cleanupPieces(setId, 10);
        assertTrue(done);
        assertEq(anyone.balance - balanceBefore, PDPFees.cleanupDeposit(), "third party receives deposit");
        assertEq(address(pdpVerifier).balance, 0, "Verifier balance is 0 after cleanup");
        assertPieceSlotsCleared(setId, 1);
    }

    function testPermissionlessDeleteAfterInactivity() public {
        uint256 setId = _createAndPopulate(1);

        // Roll past the inactivity window from the dataset creation block
        vm.roll(block.number + pdpVerifier.INACTIVITY_WINDOW() + 1);

        address anyone = address(0xDEAD);
        vm.prank(anyone);
        pdpVerifier.deleteDataSet(setId, empty);
        assertFalse(pdpVerifier.dataSetLive(setId));
    }

    function testSpCanDeleteAndCleanupInSameBlock() public {
        uint256 setId = _createAndPopulate(2);

        uint256 balanceBefore = address(this).balance;
        pdpVerifier.deleteDataSet(setId, empty);
        bool done = pdpVerifier.cleanupPieces(setId, 10);

        assertTrue(done);
        assertEq(address(this).balance - balanceBefore, PDPFees.cleanupDeposit(), "SP receives deposit in same block");
        assertEq(address(pdpVerifier).balance, 0, "Verifier balance is 0 after cleanup");
        assertPieceSlotsCleared(setId, 2);
    }

    function testAbandonedDataSetDeleteAndCleanupInOneGo() public {
        uint256 setId = _createAndPopulate(2);

        vm.roll(block.number + pdpVerifier.INACTIVITY_WINDOW() + 1);

        // One third party deletes the abandoned set and cleans up back-to-back,
        // collecting the deposit as the cleanup bounty.
        address anyone = address(0xCAFE);
        vm.deal(anyone, 10 ether);
        uint256 balanceBefore = anyone.balance;

        vm.startPrank(anyone);
        pdpVerifier.deleteDataSet(setId, empty);
        bool done = pdpVerifier.cleanupPieces(setId, 10);
        vm.stopPrank();

        assertTrue(done);
        assertEq(anyone.balance - balanceBefore, PDPFees.cleanupDeposit(), "deleter collects cleanup deposit");
        assertEq(address(pdpVerifier).balance, 0, "Verifier balance is 0 after cleanup");
        assertPieceSlotsCleared(setId, 2);
    }

    function testCleanupGateAnchorsToActivityNotDeleteEpoch() public {
        uint256 setId = _createAndPopulate(1);
        uint256 lastProven = pdpVerifier.getDataSetLastProvenEpoch(setId);
        uint256 window = pdpVerifier.INACTIVITY_WINDOW();

        // SP deletes late in its activity window
        vm.roll(lastProven + window - 100);
        pdpVerifier.deleteDataSet(setId, empty);

        // Still within the activity window: third party blocked
        address anyone = address(0xBEEF);
        vm.prank(anyone);
        vm.expectRevert(PDPVerifier.OnlyStorageProviderCanCleanupPieces.selector);
        pdpVerifier.cleanupPieces(setId, 10);

        // Just past the activity window, well before deleteEpoch + window: the gate
        // anchors to proving activity, not cleanup-mode entry.
        vm.roll(lastProven + window + 1);
        vm.deal(anyone, 10 ether);
        vm.prank(anyone);
        bool done = pdpVerifier.cleanupPieces(setId, 10);
        assertTrue(done);
        assertPieceSlotsCleared(setId, 1);
    }

    function testSpDeleteAfterAbandonmentCleanupImmediatelyPermissionless() public {
        uint256 setId = _createAndPopulate(1);

        vm.roll(block.number + pdpVerifier.INACTIVITY_WINDOW() + 1);

        // SP can always delete, but past the activity window cleanup is open to everyone
        pdpVerifier.deleteDataSet(setId, empty);

        address anyone = address(0xCAFE);
        vm.deal(anyone, 10 ether);
        vm.prank(anyone);
        assertTrue(pdpVerifier.cleanupPieces(setId, 10));
        assertPieceSlotsCleared(setId, 1);
    }

    function testCleanupLegacyActivityBaseline() public {
        uint256 setId = _createAndPopulate(1);

        // Simulate a data set created before activity tracking: lastProvenEpoch == 0
        vm.store(address(pdpVerifier), keccak256(abi.encode(setId, DATA_SET_LAST_PROVEN_EPOCH_SLOT)), bytes32(0));
        assertEq(pdpVerifier.getDataSetLastProvenEpoch(setId), 0);

        pdpVerifier.deleteDataSet(setId, empty);

        // Gate falls back to LEGACY_ACTIVITY_EPOCH (implementation deployment block)
        address notSp = address(0xBEEF);
        vm.prank(notSp);
        vm.expectRevert(PDPVerifier.OnlyStorageProviderCanCleanupPieces.selector);
        pdpVerifier.cleanupPieces(setId, 10);

        vm.roll(pdpVerifier.LEGACY_ACTIVITY_EPOCH() + pdpVerifier.INACTIVITY_WINDOW() + 1);
        vm.deal(notSp, 10 ether);
        vm.prank(notSp);
        assertTrue(pdpVerifier.cleanupPieces(setId, 10));
        assertPieceSlotsCleared(setId, 1);
    }

    function testLegacyDeletedDataSetCleanupAlwaysPermissionless() public {
        uint256 setId = _createAndPopulate(2);

        // Simulate a pre-3.4.0 delete: storageProvider zeroed, pieces left behind
        vm.store(address(pdpVerifier), keccak256(abi.encode(setId, STORAGE_PROVIDER_SLOT)), bytes32(0));

        // No activity-window gate applies; anyone can clean immediately
        address anyone = address(0xCAFE);
        vm.deal(anyone, 10 ether);
        vm.prank(anyone);
        assertTrue(pdpVerifier.cleanupPieces(setId, 10));
        assertPieceSlotsCleared(setId, 2);
    }

    function testFinalizeClearsDeprecatedCleanupModeEpochResidue() public {
        uint256 setId = _createAndPopulate(1);
        pdpVerifier.deleteDataSet(setId, empty);

        // Simulate a v3.4.0-era delete that wrote the now-deprecated gate anchor
        bytes32 slot = keccak256(abi.encode(setId, DEPRECATED_CLEANUP_MODE_EPOCH_SLOT));
        vm.store(address(pdpVerifier), slot, bytes32(uint256(123)));

        assertTrue(pdpVerifier.cleanupPieces(setId, 10));
        assertEq(vm.load(address(pdpVerifier), slot), bytes32(0), "deprecated slot cleared");
    }

    function testOnlySpCanDeleteWithinInactivityWindow() public {
        uint256 setId = _createAndPopulate(1);

        // block.number (1) <= lastProvenEpoch(0) + INACTIVITY_WINDOW, so only SP can delete
        address notSp = address(0xBEEF);
        vm.prank(notSp);
        vm.expectRevert(PDPVerifier.OnlyStorageProviderCanDelete.selector);
        pdpVerifier.deleteDataSet(setId, empty);
    }

    // --- guard conditions ---

    function testCleanupPiecesRequiresCleanupMode() public {
        uint256 setId = _createAndPopulate(1);
        // data set is still live — cleanupPieces must revert
        vm.expectRevert(PDPVerifier.DataSetNotInCleanupMode.selector);
        pdpVerifier.cleanupPieces(setId, 10);
    }

    function testCleanupPiecesFailsOnLiveZeroPieceDataSet() public {
        uint256 setId = _createAndPopulate(0);
        // live with no pieces — still not in cleanup mode
        vm.expectRevert(PDPVerifier.DataSetNotInCleanupMode.selector);
        pdpVerifier.cleanupPieces(setId, 10);
    }

    function testCleanupPiecesFailsOnNonExistentDataSet() public {
        uint256 nonExistent = pdpVerifier.getNextDataSetId();
        vm.expectRevert(PDPVerifier.DataSetNotInCleanupMode.selector);
        pdpVerifier.cleanupPieces(nonExistent, 10);
    }

    function testCleanupPiecesMaxPiecesZeroReverts() public {
        uint256 setId = _createAndPopulate(1);
        pdpVerifier.deleteDataSet(setId, empty);

        vm.expectRevert(PDPVerifier.MaxPiecesMustBePositive.selector);
        pdpVerifier.cleanupPieces(setId, 0);
    }

    function testDeleteAlreadyInCleanupReverts() public {
        uint256 setId = _createAndPopulate(1);
        pdpVerifier.deleteDataSet(setId, empty);

        vm.expectRevert(PDPVerifier.DataSetAlreadyInCleanup.selector);
        pdpVerifier.deleteDataSet(setId, empty);
    }

    // --- scheduled removals cleanup ---

    function testCleanupWithUnprocessedScheduledRemovals() public {
        uint256 setId = _createAndPopulate(2);

        // Schedule removal without processing via nextProvingPeriod
        uint256[] memory toRemove = new uint256[](1);
        toRemove[0] = 0;
        pdpVerifier.schedulePieceDeletions(setId, toRemove, empty);

        pdpVerifier.deleteDataSet(setId, empty);

        // Should finalize cleanly even with unprocessed scheduled removals
        bool done = pdpVerifier.cleanupPieces(setId, 100);
        assertTrue(done);
    }
}
