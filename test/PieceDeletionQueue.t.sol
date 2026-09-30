// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.20;

import {MockFVMTest} from "fvm-solidity/mocks/MockFVMTest.sol";
import {Cids} from "../src/Cids.sol";
import {PDPFees} from "../src/Fees.sol";
import {PDPVerifier, NO_CHALLENGE_SCHEDULED} from "../src/PDPVerifier.sol";
import {MyERC1967Proxy} from "../src/ERC1967Proxy.sol";
import {PieceHelper} from "./PieceHelper.t.sol";

contract PieceDeletionQueueHarness is PDPVerifier {
    constructor() PDPVerifier(1, 2) {}

    function useLegacyPieceStorage() external {
        legacyPieceStorageIdLimit = 0;
    }
}

contract PieceDeletionQueueTest is MockFVMTest, PieceHelper {
    PDPVerifier verifier;

    function setUp() public override {
        super.setUp();
        PieceDeletionQueueHarness implementation = new PieceDeletionQueueHarness();
        MyERC1967Proxy proxy =
            new MyERC1967Proxy(address(implementation), abi.encodeWithSelector(PDPVerifier.initialize.selector));
        verifier = PDPVerifier(address(proxy));
    }

    function testCompactQueueExceedsFormerLimitInOneCall() public {
        _testLargeRemovalQueue(false, 2001);
    }

    function testCompactQueueExceedsFormerLimitAcrossCalls() public {
        _testLargeRemovalQueue(false, 2000);
    }

    function testLegacyQueueExceedsFormerLimitInOneCall() public {
        _testLargeRemovalQueue(true, 2001);
    }

    function testLegacyQueueExceedsFormerLimitAcrossCalls() public {
        _testLargeRemovalQueue(true, 2000);
    }

    function _testLargeRemovalQueue(bool legacy, uint256 firstBatchSize) internal {
        if (legacy) {
            PieceDeletionQueueHarness(address(verifier)).useLegacyPieceStorage();
        }
        uint256 setId = verifier.createDataSet{value: PDPFees.cleanupDeposit()}(address(0), "");
        uint256 removalCount = 2001;
        Cids.Cid memory piece = makeSamplePiece(2);
        Cids.Cid[] memory pieces = new Cids.Cid[](removalCount + 1);
        for (uint256 i = 0; i < pieces.length; i++) {
            pieces[i] = piece;
        }
        verifier.addPieces(setId, address(0), pieces, "");
        uint256 challengeEpoch = block.number + 2;
        verifier.nextProvingPeriod(setId, challengeEpoch, "");

        verifier.schedulePieceDeletions(setId, _pieceIds(0, firstBatchSize), "");
        if (firstBatchSize < removalCount) {
            verifier.schedulePieceDeletions(setId, _pieceIds(firstBatchSize, removalCount), "");
        }
        assertEq(verifier.getScheduledRemovals(setId), _pieceIds(0, removalCount));
        assertEq(verifier.getNextChallengeEpoch(setId), challengeEpoch);
        assertEq(verifier.getDataSetLeafCount(setId), pieces.length * 2);

        // Duplicate protection still applies beyond the old queue limit.
        uint256[] memory duplicate = _pieceIds(removalCount - 1, removalCount);
        vm.expectRevert("Piece ID already scheduled for removal");
        verifier.schedulePieceDeletions(setId, duplicate, "");

        uint256 remaining = removalCount;
        while (remaining > 0) {
            vm.expectRevert(abi.encodeWithSelector(PDPVerifier.PendingPieceDeletions.selector, remaining));
            verifier.nextProvingPeriod(setId, challengeEpoch, "");

            uint256 batchSize = remaining > 500 ? 500 : remaining;
            verifier.processPieceDeletions(setId, batchSize);
            remaining -= batchSize;
            assertEq(verifier.getScheduledRemovals(setId), _pieceIds(0, remaining));
            assertEq(verifier.getDataSetLeafCount(setId), (remaining + 1) * 2);
            assertEq(verifier.getNextChallengeEpoch(setId), NO_CHALLENGE_SCHEDULED);
            assertFalse(verifier.pieceLive(setId, remaining));
            if (remaining > 0) {
                assertTrue(verifier.pieceLive(setId, remaining - 1));
            }
        }

        assertTrue(verifier.pieceLive(setId, removalCount));
        assertEq(verifier.getPieceCid(setId, removalCount).data, piece.data);
        verifier.nextProvingPeriod(setId, challengeEpoch, "");
        assertEq(verifier.getChallengeRange(setId), 2);
        assertEq(verifier.getNextChallengeEpoch(setId), challengeEpoch);
    }

    function _pieceIds(uint256 start, uint256 end) internal pure returns (uint256[] memory ids) {
        ids = new uint256[](end - start);
        for (uint256 i = start; i < end; i++) {
            ids[i - start] = i;
        }
    }
}
