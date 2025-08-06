// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.13;

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

contract PDPVerifierDataSetCreateDeleteTest is Test {
    TestingRecordKeeperService listener;
    PDPVerifier pdpVerifier;
    bytes empty = new bytes(0);


    function setUp() public {
        PDPVerifier pdpVerifierImpl = new PDPVerifier();
        uint256 challengeFinality = 2;
        bytes memory initializeData = abi.encodeWithSelector(
            PDPVerifier.initialize.selector,
            challengeFinality
        );
        MyERC1967Proxy proxy = new MyERC1967Proxy(address(pdpVerifierImpl), initializeData);
        pdpVerifier = PDPVerifier(address(proxy));
    }

    function testCreateDataSet() public {
        Cids.Cid memory zeroPiece;

        vm.expectEmit(true, true, false, false);
        emit IPDPEvents.DataSetCreated(0, address(this));

        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);
        assertEq(setId, 0, "First data set ID should be 0");
        assertEq(pdpVerifier.getDataSetLeafCount(setId), 0, "Data set leaf count should be 0");

        (address currentStorageProvider, address proposedStorageProvider) = pdpVerifier.getDataSetStorageProvider(setId);
        assertEq(currentStorageProvider, address(this), "Data set storage provider should be the constructor sender");
        assertEq(proposedStorageProvider, address(0), "Data set proposed storage provider should be initialized to zero address");

        assertEq(pdpVerifier.getNextChallengeEpoch(setId), 0, "Data set challenge epoch should be zero");
        assertEq(pdpVerifier.pieceLive(setId, 0), false, "Data set piece should not be live");
        assertEq(pdpVerifier.getPieceCid(setId, 0).data, zeroPiece.data, "Uninitialized piece should be empty");
        assertEq(pdpVerifier.getPieceLeafCount(setId, 0), 0, "Uninitialized piece should have zero leaves");
        assertEq(pdpVerifier.getNextChallengeEpoch(setId), 0, "Data set challenge epoch should be zero");
        assertEq(pdpVerifier.getDataSetListener(setId), address(listener), "Data set listener should be the constructor listener");
    }

    function testDeleteDataSet() public {
        vm.expectEmit(true, true, false, false);
        emit IPDPEvents.DataSetCreated(0, address(this));
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);
        vm.expectEmit(true, true, false, false);
        emit IPDPEvents.DataSetDeleted(setId, 0);
        pdpVerifier.deleteDataSet(setId, empty);
        vm.expectRevert("Data set not live");
        pdpVerifier.getDataSetLeafCount(setId);
    }

    function testOnlyStorageProviderCanDeleteDataSet() public {
         vm.expectEmit(true, true, false, false);
        emit IPDPEvents.DataSetCreated(0, address(this));
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);
        // Create a new address to act as a non-storage-provider
        address nonStorageProvider = address(0x1234);
        // Expect revert when non-storage-provider tries to delete the data set
        vm.prank(nonStorageProvider);
        vm.expectRevert("Only the storage provider can delete data sets");
        pdpVerifier.deleteDataSet(setId, empty);

        // Now verify the storage provider can delete the data set
        vm.expectEmit(true, true, false, false);
        emit IPDPEvents.DataSetDeleted(setId, 0);
        pdpVerifier.deleteDataSet(setId, empty);
        vm.expectRevert("Data set not live");
        pdpVerifier.getDataSetStorageProvider(setId);
    }

    // TODO: once we have addPieces we should test deletion of a non empty data set
    function testCannotDeleteNonExistentDataSet() public {
        vm.expectRevert("data set id out of bounds");
        pdpVerifier.deleteDataSet(0, empty);
    }

    function testMethodsOnDeletedDataSetFails() public {
        vm.expectEmit(true, true, false, false);
        emit IPDPEvents.DataSetCreated(0, address(this));
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);

        vm.expectEmit(true, true, false, false);
        emit IPDPEvents.DataSetDeleted(setId, 0);
        pdpVerifier.deleteDataSet(setId, empty);
        vm.expectRevert("Only the storage provider can delete data sets");
        pdpVerifier.deleteDataSet(setId, empty );
        vm.expectRevert("Data set not live");
        pdpVerifier.getDataSetStorageProvider(setId);
        vm.expectRevert("Data set not live");
        pdpVerifier.getDataSetLeafCount(setId);
        vm.expectRevert("Data set not live");
        pdpVerifier.getDataSetListener(setId);
        vm.expectRevert("Data set not live");
        pdpVerifier.getPieceCid(setId, 0);
        vm.expectRevert("Data set not live");
        pdpVerifier.getPieceLeafCount(setId, 0);
        vm.expectRevert("Data set not live");
        pdpVerifier.getNextChallengeEpoch(setId);
        vm.expectRevert("Data set not live");
        pdpVerifier.addPieces(setId, new IPDPTypes.PieceData[](0), empty);
    }

    function testGetDataSetID() public {
        vm.expectEmit(true, true, false, false);
        emit IPDPEvents.DataSetCreated(0, address(this));
        pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);
        vm.expectEmit(true, true, false, false);
        emit IPDPEvents.DataSetCreated(1, address(this));
        pdpVerifier.createDataSet{value: PDPFees.sybilFee()} (address(listener), empty);
        assertEq(2, pdpVerifier.getNextDataSetId(), "Next data set ID should be 2");
        assertEq(2, pdpVerifier.getNextDataSetId(), "Next data set ID should be 2");
    }

    receive() external payable {}

    function testCreateDataSetFeeHandling() public {
        uint256 sybilFee = PDPFees.sybilFee();

        // Test 1: Fails when sending not enough for sybil fee
        vm.expectRevert("sybil fee not met");
        pdpVerifier.createDataSet{value: sybilFee - 1}(address(listener), empty);

        // Test 2: Returns funds over the sybil fee back to the sender
        uint256 excessAmount = 1 ether;
        uint256 initialBalance = address(this).balance;

        uint256 setId = pdpVerifier.createDataSet{value: sybilFee + excessAmount}(address(listener), empty);

        uint256 finalBalance = address(this).balance;
        uint256 refundedAmount = finalBalance - (initialBalance - sybilFee - excessAmount);
        assertEq(refundedAmount, excessAmount, "Excess amount should be refunded");

        // Additional checks to ensure the data set was created correctly
        assertEq(pdpVerifier.getDataSetLeafCount(setId), 0, "Data set leaf count should be 0");
        (address currentStorageProvider, address proposedStorageProvider) = pdpVerifier.getDataSetStorageProvider(setId);
        assertEq(currentStorageProvider, address(this), "Data set storage provider should be the constructor sender");
        assertEq(proposedStorageProvider, address(0), "Data set proposed storage provider should be initialized to zero address");
    }
}

contract PDPVerifierStorageProviderTest is Test {
    PDPVerifier pdpVerifier;
    TestingRecordKeeperService listener;
    address public storageProvider;
    address public nextStorageProvider;
    address public nonStorageProvider;
    bytes empty = new bytes(0);


    function setUp() public {
        PDPVerifier pdpVerifierImpl = new PDPVerifier();
        bytes memory initializeData = abi.encodeWithSelector(
            PDPVerifier.initialize.selector,
            2
        );
        MyERC1967Proxy proxy = new MyERC1967Proxy(address(pdpVerifierImpl), initializeData);
        pdpVerifier = PDPVerifier(address(proxy));
        listener = new TestingRecordKeeperService();

        storageProvider = address(this);
        nextStorageProvider = address(0x1234);
        nonStorageProvider = address(0xffff);
    }

    function testStorageProviderTransfer() public {
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);
        pdpVerifier.proposeDataSetStorageProvider(setId, nextStorageProvider);
        (address currentStorageProviderStart, address proposedStorageProviderStart) = pdpVerifier.getDataSetStorageProvider(setId);
        assertEq(currentStorageProviderStart, storageProvider, "Data set storage provider should be the constructor sender");
        assertEq(proposedStorageProviderStart, nextStorageProvider, "Data set proposed storage provider should make the one proposed");
        vm.prank(nextStorageProvider);

        vm.expectEmit(true, true, false, false);
        emit IPDPEvents.StorageProviderChanged(setId, storageProvider, nextStorageProvider);
        pdpVerifier.claimDataSetStorageProvider(setId, empty);
        (address currentStorageProviderEnd, address proposedStorageProviderEnd) = pdpVerifier.getDataSetStorageProvider(setId);
        assertEq(currentStorageProviderEnd, nextStorageProvider, "Data set storage provider should be the next provider");
        assertEq(proposedStorageProviderEnd, address(0), "Data set proposed storage provider should be zero address");
    }

    function testStorageProviderProposalReset() public {
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);
        pdpVerifier.proposeDataSetStorageProvider(setId, nextStorageProvider);
        pdpVerifier.proposeDataSetStorageProvider(setId, storageProvider);
        (address currentStorageProviderEnd, address proposedStorageProviderEnd) = pdpVerifier.getDataSetStorageProvider(setId);
        assertEq(currentStorageProviderEnd, storageProvider, "Data set storage provider should be the constructor sender");
        assertEq(proposedStorageProviderEnd, address(0), "Data set proposed storage provider should be zero address");
    }

    function testStorageProviderPermissionsRequired() public {
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);
        vm.prank(nonStorageProvider);
        vm.expectRevert("Only the current storage provider can propose a new storage provider");
        pdpVerifier.proposeDataSetStorageProvider(setId, nextStorageProvider);

        // Now send proposal from actual storage provider
        pdpVerifier.proposeDataSetStorageProvider(setId, nextStorageProvider);

        // Proposed storage provider has no extra permissions
        vm.prank(nextStorageProvider);
        vm.expectRevert("Only the current storage provider can propose a new storage provider");
        pdpVerifier.proposeDataSetStorageProvider(setId, nonStorageProvider);

        vm.prank(nonStorageProvider);
        vm.expectRevert("Only the proposed storage provider can claim storage provider role");
        pdpVerifier.claimDataSetStorageProvider(setId, empty);
    }

    function testScheduleRemovePiecesOnlyStorageProvider() public {
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);
        Cids.Cid memory testCid = Cids.Cid(abi.encodePacked("test"));
        IPDPTypes.PieceData[] memory pieceDataArray = new IPDPTypes.PieceData[](1);
        pieceDataArray[0] = IPDPTypes.PieceData(testCid, 100 * pdpVerifier.LEAF_SIZE());
        pdpVerifier.addPieces(setId, pieceDataArray, empty);

        uint256[] memory pieceIdsToRemove = new uint256[](1);
        pieceIdsToRemove[0] = 0;

        vm.prank(nonStorageProvider);
        vm.expectRevert("Only the storage provider can schedule removal of pieces");
        pdpVerifier.schedulePieceDeletions(setId, pieceIdsToRemove, empty);
    }
}


contract PDPVerifierDataSetMutateTest is Test {
    uint256 constant challengeFinalityDelay = 2;

    PDPVerifier pdpVerifier;
    TestingRecordKeeperService listener;
    bytes empty = new bytes(0);


    function setUp() public {
        PDPVerifier pdpVerifierImpl = new PDPVerifier();
        bytes memory initializeData = abi.encodeWithSelector(
            PDPVerifier.initialize.selector,
            challengeFinalityDelay
        );
        MyERC1967Proxy proxy = new MyERC1967Proxy(address(pdpVerifierImpl), initializeData);
        pdpVerifier = PDPVerifier(address(proxy));
    }

    function testAddPiece() public {
        vm.expectEmit(true, true, false, false);
        emit IPDPEvents.DataSetCreated(0, address(this));
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);

        IPDPTypes.PieceData[] memory pieces = new IPDPTypes.PieceData[](1);
        pieces[0] = IPDPTypes.PieceData(Cids.Cid(abi.encodePacked("test")), 64);

        vm.expectEmit(true, true, false, false);
        emit IPDPEvents.PiecesAdded(setId, new uint256[](0));
        uint256 pieceId = pdpVerifier.addPieces(setId, pieces, empty);
        assertEq(pdpVerifier.getChallengeRange(setId), 0);

        // flush add
        vm.expectEmit(true, true, false, false);
        emit IPDPEvents.NextProvingPeriod(setId, block.number + challengeFinalityDelay, 2);
        pdpVerifier.nextProvingPeriod(setId, block.number + challengeFinalityDelay, empty);

        uint256 leafCount = pieces[0].rawSize / 32;
        assertEq(pdpVerifier.getDataSetLeafCount(setId), leafCount);
        assertEq(pdpVerifier.getNextChallengeEpoch(setId), block.number + challengeFinalityDelay);
        assertEq(pdpVerifier.getChallengeRange(setId), leafCount);

        assertTrue(pdpVerifier.pieceLive(setId, pieceId));
        assertEq(pdpVerifier.getPieceCid(setId, pieceId).data, pieces[0].piece.data);
        assertEq(pdpVerifier.getPieceLeafCount(setId, pieceId), leafCount);

        assertEq(pdpVerifier.getNextPieceId(setId), 1);
    }

    function testAddMultiplePieces() public {
        vm.expectEmit(true, true, false, false);
        emit IPDPEvents.DataSetCreated(0, address(this));
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);
        IPDPTypes.PieceData[] memory pieces = new IPDPTypes.PieceData[](2);
        pieces[0] = IPDPTypes.PieceData(Cids.Cid(abi.encodePacked("test1")), 64);
        pieces[1] = IPDPTypes.PieceData(Cids.Cid(abi.encodePacked("test2")), 128);

        vm.expectEmit(true, true, false, false);
        uint256[] memory pieceIds = new uint256[](2);
        pieceIds[0] = 0;
        pieceIds[1] = 1;
        emit IPDPEvents.PiecesAdded(setId, pieceIds);
        uint256 firstId = pdpVerifier.addPieces(setId, pieces, empty);
        assertEq(firstId, 0);
        // flush add
        vm.expectEmit(true, true, true, false);
        emit IPDPEvents.NextProvingPeriod(setId, block.number + challengeFinalityDelay, 6);
        pdpVerifier.nextProvingPeriod(setId, block.number + challengeFinalityDelay, empty);

        uint256 expectedLeafCount = pieces[0].rawSize / 32 + pieces[1].rawSize / 32;
        assertEq(pdpVerifier.getDataSetLeafCount(setId), expectedLeafCount);
        assertEq(pdpVerifier.getNextChallengeEpoch(setId), block.number + challengeFinalityDelay);

        assertTrue(pdpVerifier.pieceLive(setId, firstId));
        assertTrue(pdpVerifier.pieceLive(setId, firstId + 1));
        assertEq(pdpVerifier.getPieceCid(setId, firstId).data, pieces[0].piece.data);
        assertEq(pdpVerifier.getPieceCid(setId, firstId + 1).data, pieces[1].piece.data);

        assertEq(pdpVerifier.getPieceLeafCount(setId, firstId), pieces[0].rawSize / 32);
        assertEq(pdpVerifier.getPieceLeafCount(setId, firstId + 1), pieces[1].rawSize / 32);
        assertEq(pdpVerifier.getNextPieceId(setId), 2);
    }

    function expectIndexedError(uint256 index, string memory expectedMessage) internal {
        vm.expectRevert(abi.encodeWithSelector(PDPVerifier.IndexedError.selector, index, expectedMessage));
    }

    function testAddBadPiece() public {
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);
        IPDPTypes.PieceData[] memory pieces = new IPDPTypes.PieceData[](1);

        // Fail when piece size is not a multiple of 32
        pieces[0] = IPDPTypes.PieceData(Cids.Cid(abi.encodePacked("test")), 63);
        expectIndexedError(0, "Size must be a multiple of 32");
        pdpVerifier.addPieces(setId, pieces, empty);

        // Fail when piece size is zero
        pieces[0] = IPDPTypes.PieceData(Cids.Cid(abi.encodePacked("test")), 0);
        expectIndexedError(0, "Size must be greater than 0");
        pdpVerifier.addPieces(setId, pieces, empty);

        // Fail when piece size is too large
        pieces[0] = IPDPTypes.PieceData(Cids.Cid(abi.encodePacked("test")), pdpVerifier.MAX_PIECE_SIZE() + 32);
        expectIndexedError(0, "Piece size must be less than 2^50");
        pdpVerifier.addPieces(setId, pieces, empty);

        // Fail when not adding any pieces;
        IPDPTypes.PieceData[] memory emptyPieces = new IPDPTypes.PieceData[](0);
        vm.expectRevert("Must add at least one piece");
        pdpVerifier.addPieces(setId, emptyPieces, empty);

        // Fail when data set is no longer live
        pieces[0] = IPDPTypes.PieceData(Cids.Cid(abi.encodePacked("test")), 32);
        pdpVerifier.deleteDataSet(setId, empty);
        vm.expectRevert("Data set not live");
        pdpVerifier.addPieces(setId, pieces, empty);
    }

    function testAddBadPiecesBatched() public {
        // Add one bad piece, message fails on bad index
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);
        IPDPTypes.PieceData[] memory pieces = new IPDPTypes.PieceData[](4);
        pieces[0] = IPDPTypes.PieceData(Cids.Cid(abi.encodePacked("test")), 32);
        pieces[1] = IPDPTypes.PieceData(Cids.Cid(abi.encodePacked("test")), 32);
        pieces[2] = IPDPTypes.PieceData(Cids.Cid(abi.encodePacked("test")), 32);
        pieces[3] = IPDPTypes.PieceData(Cids.Cid(abi.encodePacked("test")), 31);

        expectIndexedError(3, "Size must be a multiple of 32");
        pdpVerifier.addPieces(setId, pieces, empty);

        // Add multiple bad pieces, message fails on first bad index
        pieces[0] = IPDPTypes.PieceData(Cids.Cid(abi.encodePacked("test")), 63);
        expectIndexedError(0, "Size must be a multiple of 32");
        pdpVerifier.addPieces(setId, pieces, empty);
    }

    function testRemovePiece() public {
        // Add one piece
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);
        IPDPTypes.PieceData[] memory pieces = new IPDPTypes.PieceData[](1);
        pieces[0] = IPDPTypes.PieceData(Cids.Cid(abi.encodePacked("test")), 64);
        pdpVerifier.addPieces(setId, pieces, empty);
        assertEq(pdpVerifier.getNextChallengeEpoch(setId), pdpVerifier.NO_CHALLENGE_SCHEDULED()); // Not updated on first add anymore
        pdpVerifier.nextProvingPeriod(setId, block.number + challengeFinalityDelay, empty);
        assertEq(pdpVerifier.getNextChallengeEpoch(setId), block.number + challengeFinalityDelay);


        // Remove piece
        uint256[] memory toRemove = new uint256[](1);
        toRemove[0] = 0;
        pdpVerifier.schedulePieceDeletions(setId, toRemove, empty);

        vm.expectEmit(true, true, false, false);
        emit IPDPEvents.PiecesRemoved(setId, toRemove);
        pdpVerifier.nextProvingPeriod(setId, block.number + challengeFinalityDelay, empty); // flush

        assertEq(pdpVerifier.getNextChallengeEpoch(setId), pdpVerifier.NO_CHALLENGE_SCHEDULED());
        assertEq(pdpVerifier.pieceLive(setId, 0), false);
        assertEq(pdpVerifier.getNextPieceId(setId), 1);
        assertEq(pdpVerifier.getDataSetLeafCount(setId), 0);
        bytes memory emptyCidData = new bytes(0);
        assertEq(pdpVerifier.getPieceCid(setId, 0).data, emptyCidData);
        assertEq(pdpVerifier.getPieceLeafCount(setId, 0), 0);

    }

    function testCannotScheduleRemovalOnNonLiveDataSet() public {
        // Create a data set
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);

        // Add a piece to the data set
        IPDPTypes.PieceData[] memory pieces = new IPDPTypes.PieceData[](1);
        pieces[0] = IPDPTypes.PieceData(Cids.Cid(abi.encodePacked("test")), 64);
        pdpVerifier.addPieces(setId, pieces, empty);

        // Delete the data set
        pdpVerifier.deleteDataSet(setId, empty);

        // Attempt to schedule removal of the piece, which should fail
        uint256[] memory pieceIds = new uint256[](1);
        pieceIds[0] = 0;
        vm.expectRevert("Data set not live");
        pdpVerifier.schedulePieceDeletions(setId, pieceIds, empty);
    }

    function testRemovePieceBatch() public {
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);
        IPDPTypes.PieceData[] memory pieces = new IPDPTypes.PieceData[](3);
        pieces[0] = IPDPTypes.PieceData(Cids.Cid(abi.encodePacked("test1")), 64);
        pieces[1] = IPDPTypes.PieceData(Cids.Cid(abi.encodePacked("test2")), 64);
        pieces[2] = IPDPTypes.PieceData(Cids.Cid(abi.encodePacked("test")), 64);
        pdpVerifier.addPieces(setId, pieces, empty);
        uint256[] memory toRemove = new uint256[](2);
        toRemove[0] = 0;
        toRemove[1] = 2;
        pdpVerifier.schedulePieceDeletions(setId, toRemove, empty);

        vm.expectEmit(true, true, false, false);
        emit IPDPEvents.PiecesRemoved(setId, toRemove);
        pdpVerifier.nextProvingPeriod(setId, block.number + challengeFinalityDelay, empty); // flush

        assertEq(pdpVerifier.pieceLive(setId, 0), false);
        assertEq(pdpVerifier.pieceLive(setId, 1), true);
        assertEq(pdpVerifier.pieceLive(setId, 2), false);

        assertEq(pdpVerifier.getNextPieceId(setId), 3);
        assertEq(pdpVerifier.getDataSetLeafCount(setId), 64/32);
        assertEq(pdpVerifier.getNextChallengeEpoch(setId), block.number + challengeFinalityDelay);

        bytes memory emptyCidData = new bytes(0);
        assertEq(pdpVerifier.getPieceCid(setId, 0).data, emptyCidData);
        assertEq(pdpVerifier.getPieceCid(setId, 1).data, pieces[1].piece.data);
        assertEq(pdpVerifier.getPieceCid(setId, 2).data, emptyCidData);

        assertEq(pdpVerifier.getPieceLeafCount(setId, 0), 0);
        assertEq(pdpVerifier.getPieceLeafCount(setId, 1), 64/32);
        assertEq(pdpVerifier.getPieceLeafCount(setId, 2), 0);

    }

    function testRemoveFuturePieces() public {
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);
        IPDPTypes.PieceData[] memory pieces = new IPDPTypes.PieceData[](1);
        pieces[0] = IPDPTypes.PieceData(Cids.Cid(abi.encodePacked("test")), 64);
        pdpVerifier.addPieces(setId, pieces, empty);
        assertEq(true, pdpVerifier.pieceLive(setId, 0));
        assertEq(false, pdpVerifier.pieceLive(setId, 1));
        uint256[] memory toRemove = new uint256[](2);

        // Scheduling an un-added piece for removal should fail
        toRemove[0] = 0; // current piece
        toRemove[1] = 1; // future piece
        vm.expectRevert("Can only schedule removal of existing pieces");
        pdpVerifier.schedulePieceDeletions(setId, toRemove, empty);
        // Actual removal does not fail
        pdpVerifier.nextProvingPeriod(setId, block.number + challengeFinalityDelay, empty);

        // Scheduling both unchallengeable and challengeable pieces for removal succeeds
        // scheduling duplicate ids in both cases succeeds
        uint256[] memory toRemove2 = new uint256[](4);
        pdpVerifier.addPieces(setId, pieces, empty);
        toRemove2[0] = 0; // current challengeable piece
        toRemove2[1] = 1; // current unchallengeable piece
        toRemove2[2] = 0; // duplicate challengeable
        toRemove2[3] = 1; // duplicate unchallengeable
        // state exists for both pieces
        assertEq(true, pdpVerifier.pieceLive(setId, 0));
        assertEq(true, pdpVerifier.pieceLive(setId, 1));
        // only piece 0 is challengeable
        assertEq(true, pdpVerifier.pieceChallengable(setId, 0));
        assertEq(false, pdpVerifier.pieceChallengable(setId, 1));
        pdpVerifier.schedulePieceDeletions(setId, toRemove2, empty);
        pdpVerifier.nextProvingPeriod(setId, block.number + challengeFinalityDelay, empty);

        assertEq(false, pdpVerifier.pieceLive(setId, 0));
        assertEq(false, pdpVerifier.pieceLive(setId, 1));
    }

    function testExtraDataMaxSizeLimit() public {
        // Generate extra data that exceeds the max size (2KB)
        bytes memory tooLargeExtraData = new bytes(2049); // 2KB + 1 byte
        for (uint i = 0; i < tooLargeExtraData.length; i++) {
            tooLargeExtraData[i] = 0x41; // ASCII 'A'
        }

        // First test createDataSet with too large extra data
        vm.expectRevert("Extra data too large");
        pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), tooLargeExtraData);

        // Now create data set
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);
        IPDPTypes.PieceData[] memory pieces = new IPDPTypes.PieceData[](1);

        // Test addPieces with too large extra data
        pieces[0] = IPDPTypes.PieceData(Cids.Cid(abi.encodePacked("test")), 64);
        vm.expectRevert("Extra data too large");
        pdpVerifier.addPieces(setId, pieces, tooLargeExtraData);

        // Now actually add piece id 0
        pdpVerifier.addPieces(setId, pieces, empty);

        // Test schedulePieceDeletions with too large extra data
        uint256[] memory pieceIds = new uint256[](1);
        pieceIds[0] = 0;
        vm.expectRevert("Extra data too large");
        pdpVerifier.schedulePieceDeletions(setId, pieceIds, tooLargeExtraData);

        // Test nextProvingPeriod with too large extra data
        vm.expectRevert("Extra data too large");
        pdpVerifier.nextProvingPeriod(setId, block.number + 10, tooLargeExtraData);

        // Test deleteDataSet with too large extra data
        vm.expectRevert("Extra data too large");
        pdpVerifier.deleteDataSet(setId, tooLargeExtraData);
    }

    function testOnlyStorageProviderCanModifyDataSet() public {
        // Setup a piece we can add
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);
        IPDPTypes.PieceData[] memory pieces = new IPDPTypes.PieceData[](1);
        pieces[0] = IPDPTypes.PieceData(Cids.Cid(abi.encodePacked("test")), 64);

        // First add a piece as the storage provider so we can test removal
        pdpVerifier.addPieces(setId, pieces, empty);

        address nonStorageProvider = address(0xC0FFEE);
        // Try to add pieces as non-storage-provider
        vm.prank(nonStorageProvider);
        vm.expectRevert("Only the storage provider can add pieces");
        pdpVerifier.addPieces(setId, pieces, empty);

        // Try to delete data set as non-storage-provider
        vm.prank(nonStorageProvider);
        vm.expectRevert("Only the storage provider can delete data sets");
        pdpVerifier.deleteDataSet(setId, empty);

        // Try to schedule removals as non-storage-provider
        uint256[] memory pieceIds = new uint256[](1);
        pieceIds[0] = 0;
        vm.prank(nonStorageProvider);
        vm.expectRevert("Only the storage provider can schedule removal of pieces");
        pdpVerifier.schedulePieceDeletions(setId, pieceIds, empty);

        // Try to provePossession as non-storage-provider
        vm.prank(nonStorageProvider);
        IPDPTypes.Proof[] memory proofs = new IPDPTypes.Proof[](1);
        proofs[0] = IPDPTypes.Proof(bytes32(abi.encodePacked("test")), new bytes32[](0));
        vm.expectRevert("Only the storage provider can prove possession");
        pdpVerifier.provePossession(setId, proofs);

        // Try to call nextProvingPeriod as non-storage-provider
        vm.prank(nonStorageProvider);
        vm.expectRevert("only the storage provider can move to next proving period");
        pdpVerifier.nextProvingPeriod(setId, block.number + 10, empty);
    }

    function testNextProvingPeriodChallengeEpochTooSoon() public {
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);
        // Add a piece to the data set (otherwise nextProvingPeriod fails waiting for leaves)
        IPDPTypes.PieceData[] memory pieces = new IPDPTypes.PieceData[](1);
        pieces[0] = IPDPTypes.PieceData(Cids.Cid(abi.encodePacked("test")), 64);
        pdpVerifier.addPieces(setId, pieces, empty);

        // Current block number
        uint256 currentBlock = block.number;

        // Try to call nextProvingPeriod with a challenge epoch that is not at least
        // challengeFinality epochs in the future
        uint256 tooSoonEpoch = currentBlock + challengeFinalityDelay - 1;

        // Expect revert with the specific error message
        vm.expectRevert("challenge epoch must be at least challengeFinality epochs in the future");
        pdpVerifier.nextProvingPeriod(setId, tooSoonEpoch, "");

        // Set challenge epoch to exactly challengeFinality epochs in the future
        // This should work (not revert)
        uint256 validEpoch = currentBlock + challengeFinalityDelay;

        // This call should succeed
        pdpVerifier.nextProvingPeriod(setId, validEpoch, "");

        // Verify the challenge epoch was set correctly
        assertEq(pdpVerifier.getNextChallengeEpoch(setId), validEpoch);
    }

    function testNextProvingPeriodWithNoData() public {
        // Get the NO_CHALLENGE_SCHEDULED constant value for clarity
        uint256 NO_CHALLENGE = pdpVerifier.NO_CHALLENGE_SCHEDULED();

        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);

        // Initial state should be NO_CHALLENGE
        assertEq(pdpVerifier.getNextChallengeEpoch(setId), NO_CHALLENGE, "Initial state should be NO_CHALLENGE");

        // Try to set next proving period with various values
        vm.expectRevert("can only start proving once leaves are added");
        pdpVerifier.nextProvingPeriod(setId, block.number + 100, empty);

        vm.expectRevert("can only start proving once leaves are added");
        pdpVerifier.nextProvingPeriod(setId, block.number + challengeFinalityDelay, empty);

        vm.expectRevert("can only start proving once leaves are added");
        pdpVerifier.nextProvingPeriod(setId, type(uint256).max, empty);
    }

    function testNextProvingPeriodRevertsOnEmptyDataSet() public {
        // Create a new data set
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);

        // Try to call nextProvingPeriod on the empty data set
        // Should revert because no leaves have been added yet
        vm.expectRevert("can only start proving once leaves are added");
        pdpVerifier.nextProvingPeriod(
            setId,
            block.number + challengeFinalityDelay,
            empty
        );
    }

    function testEmitDataSetEmptyEvent() public {
        // Create a data set with one piece
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);

        IPDPTypes.PieceData[] memory pieces = new IPDPTypes.PieceData[](1);
        pieces[0] = IPDPTypes.PieceData(Cids.Cid(abi.encodePacked("test")), 64);
        pdpVerifier.addPieces(setId, pieces, empty);

        // Schedule piece for removal
        uint256[] memory toRemove = new uint256[](1);
        toRemove[0] = 0;
        pdpVerifier.schedulePieceDeletions(setId, toRemove, empty);

        // Expect DataSetEmpty event when calling nextProvingPeriod
        vm.expectEmit(true, false, false, false);
        emit IPDPEvents.DataSetEmpty(setId);

        // Call nextProvingPeriod which should remove the piece and emit the event
        pdpVerifier.nextProvingPeriod(setId, block.number + challengeFinalityDelay, empty);

        // Verify the data set is indeed empty
        assertEq(pdpVerifier.getDataSetLeafCount(setId), 0);
        assertEq(pdpVerifier.getNextChallengeEpoch(setId), 0);
        assertEq(pdpVerifier.getDataSetLastProvenEpoch(setId), 0);
    }
}

contract PDPVerifierPaginationTest is Test {
    PDPVerifier pdpVerifier;
    TestingRecordKeeperService listener;
    bytes empty = new bytes(0);

    function setUp() public {
        PDPVerifier pdpVerifierImpl = new PDPVerifier();
        uint256 challengeFinality = 2;
        bytes memory initializeData = abi.encodeWithSelector(
            PDPVerifier.initialize.selector,
            challengeFinality
        );
        MyERC1967Proxy proxy = new MyERC1967Proxy(address(pdpVerifierImpl), initializeData);
        pdpVerifier = PDPVerifier(address(proxy));
        listener = new TestingRecordKeeperService();
    }


    function testGetActivePiecesEmpty() public {
        // Create empty data set and test
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);

        (Cids.Cid[] memory pieces, uint256[] memory ids,
         uint256[] memory sizes, bool hasMore) = pdpVerifier.getActivePieces(setId, 0, 10);

        assertEq(pieces.length, 0, "Should return empty array for empty data set");
        assertEq(ids.length, 0, "Should return empty IDs array");
        assertEq(sizes.length, 0, "Should return empty sizes array");
        assertEq(hasMore, false, "Should not have more items");

        // Also verify with getActivePieceCount
        assertEq(pdpVerifier.getActivePieceCount(setId), 0, "Empty data set should have 0 active pieces");
    }

    function testGetActivePiecesPagination() public {
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);

        // Add 15 pieces
        IPDPTypes.PieceData[] memory testPieces = new IPDPTypes.PieceData[](15);
        for (uint i = 0; i < 15; i++) {
            testPieces[i] = IPDPTypes.PieceData({
                piece: Cids.Cid(abi.encodePacked("test", i)),
                rawSize: 1024 * (i + 1)
            });
        }

        uint256 firstPieceId = pdpVerifier.addPieces(setId, testPieces, empty);
        assertEq(firstPieceId, 0, "First piece ID should be 0");

        // Verify total count
        assertEq(pdpVerifier.getActivePieceCount(setId), 15, "Should have 15 active pieces");

        // Test first page
        (Cids.Cid[] memory pieces1, uint256[] memory ids1, uint256[] memory sizes1, bool hasMore1) =
            pdpVerifier.getActivePieces(setId, 0, 5);
        assertEq(pieces1.length, 5, "First page should have 5 pieces");
        assertEq(ids1.length, 5, "First page should have 5 IDs");
        assertEq(sizes1.length, 5, "First page should have 5 sizes");
        assertEq(hasMore1, true, "Should have more items after first page");
        assertEq(sizes1[0], 1024, "First piece size should be 1024");
        assertEq(ids1[0], 0, "First piece ID should be 0");

        // Test second page
        (Cids.Cid[] memory pieces2, uint256[] memory ids2, uint256[] memory sizes2, bool hasMore2) =
            pdpVerifier.getActivePieces(setId, 5, 5);
        assertEq(pieces2.length, 5, "Second page should have 5 pieces");
        assertEq(hasMore2, true, "Should have more items after second page");
        assertEq(ids2[0], 5, "First piece ID on second page should be 5");
        assertEq(sizes2[0], 6144, "First piece size on second page should be 6144 (1024 * 6)");

        // Test last page
        (Cids.Cid[] memory pieces3, uint256[] memory ids3, uint256[] memory sizes3, bool hasMore3) =
            pdpVerifier.getActivePieces(setId, 10, 5);
        assertEq(pieces3.length, 5, "Last page should have 5 pieces");
        assertEq(hasMore3, false, "Should not have more items after last page");
        assertEq(ids3[0], 10, "First piece ID on last page should be 10");
    }

    function testGetActivePiecesWithDeleted() public {
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);

        // Add pieces
        IPDPTypes.PieceData[] memory testPieces = new IPDPTypes.PieceData[](10);
        for (uint i = 0; i < 10; i++) {
            testPieces[i] = IPDPTypes.PieceData({
                piece: Cids.Cid(abi.encodePacked("test", i)),
                rawSize: 1024
            });
        }
        uint256 firstPieceId = pdpVerifier.addPieces(setId, testPieces, empty);

        // Schedule removal of pieces 2, 4, 6 (indices 1, 3, 5)
        uint256[] memory toRemove = new uint256[](3);
        toRemove[0] = firstPieceId + 1;  // Piece at index 1
        toRemove[1] = firstPieceId + 3;  // Piece at index 3
        toRemove[2] = firstPieceId + 5;  // Piece at index 5
        pdpVerifier.schedulePieceDeletions(setId, toRemove, empty);

        // Move to next proving period to make removals effective
        uint256 challengeFinalityDelay = pdpVerifier.getChallengeFinality();
        pdpVerifier.nextProvingPeriod(setId, block.number + challengeFinalityDelay, empty);

        // Should return only 7 active pieces
        (Cids.Cid[] memory pieces, uint256[] memory ids, uint256[] memory sizes, bool hasMore) =
            pdpVerifier.getActivePieces(setId, 0, 10);
        assertEq(pieces.length, 7, "Should have 7 active pieces after deletions");
        assertEq(hasMore, false, "Should not have more items");

        // Verify count matches
        assertEq(pdpVerifier.getActivePieceCount(setId), 7, "Should have 7 active pieces count");

        // Verify the correct pieces are returned (0, 2, 4, 6, 7, 8, 9)
        assertEq(ids[0], 0, "First active piece should be 0");
        assertEq(ids[1], 2, "Second active piece should be 2");
        assertEq(ids[2], 4, "Third active piece should be 4");
        assertEq(ids[3], 6, "Fourth active piece should be 6");
        assertEq(ids[4], 7, "Fifth active piece should be 7");
    }

    function testGetActivePiecesEdgeCases() public {
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);

        // Add 5 pieces
        IPDPTypes.PieceData[] memory testPieces = new IPDPTypes.PieceData[](5);
        for (uint i = 0; i < 5; i++) {
            testPieces[i] = IPDPTypes.PieceData({
                piece: Cids.Cid(abi.encodePacked("test", i)),
                rawSize: 1024
            });
        }
        pdpVerifier.addPieces(setId, testPieces, empty);

        // Verify count
        assertEq(pdpVerifier.getActivePieceCount(setId), 5, "Should have 5 active pieces");

        // Test offset beyond range
        (Cids.Cid[] memory pieces1, uint256[] memory ids1, uint256[] memory sizes1, bool hasMore1) =
            pdpVerifier.getActivePieces(setId, 10, 5);
        assertEq(pieces1.length, 0, "Should return empty when offset beyond range");
        assertEq(hasMore1, false, "Should not have more items");

        // Test limit 0 - should revert now
        vm.expectRevert("Limit must be greater than 0");
        pdpVerifier.getActivePieces(setId, 0, 0);

        // Test limit exceeding available
        (Cids.Cid[] memory pieces3, uint256[] memory ids3, uint256[] memory sizes3, bool hasMore3) =
            pdpVerifier.getActivePieces(setId, 3, 10);
        assertEq(pieces3.length, 2, "Should return only 2 pieces from offset 3");
        assertEq(hasMore3, false, "Should not have more items");
        assertEq(ids3[0], 3, "First ID should be 3");
        assertEq(ids3[1], 4, "Second ID should be 4");
    }

    function testGetActivePiecesNotLive() public {
        // Test with invalid data set ID
        vm.expectRevert("Data set not live");
        pdpVerifier.getActivePieces(999, 0, 10);

        // Also test getActivePieceCount
        vm.expectRevert("Data set not live");
        pdpVerifier.getActivePieceCount(999);
    }

    function testGetActivePiecesHasMore() public {
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);

        // Add exactly 10 pieces
        IPDPTypes.PieceData[] memory testPieces = new IPDPTypes.PieceData[](10);
        for (uint i = 0; i < 10; i++) {
            testPieces[i] = IPDPTypes.PieceData({
                piece: Cids.Cid(abi.encodePacked("test", i)),
                rawSize: 1024
            });
        }
        pdpVerifier.addPieces(setId, testPieces, empty);

        // Test exact boundary - requesting exactly all items
        (,,, bool hasMore1) = pdpVerifier.getActivePieces(setId, 0, 10);
        assertEq(hasMore1, false, "Should not have more when requesting exactly all items");

        // Test one less than total - should have more
        (,,, bool hasMore2) = pdpVerifier.getActivePieces(setId, 0, 9);
        assertEq(hasMore2, true, "Should have more when requesting less than total");

        // Test at offset with remaining items
        (,,, bool hasMore3) = pdpVerifier.getActivePieces(setId, 5, 4);
        assertEq(hasMore3, true, "Should have more when 1 item remains");

        // Test at offset with no remaining items
        (,,, bool hasMore4) = pdpVerifier.getActivePieces(setId, 5, 5);
        assertEq(hasMore4, false, "Should not have more when requesting exactly remaining items");
    }

    function testGetActivePiecesLargeSet() public {
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);

        // Add 100 pieces
        IPDPTypes.PieceData[] memory testPieces = new IPDPTypes.PieceData[](100);
        for (uint i = 0; i < 100; i++) {
            testPieces[i] = IPDPTypes.PieceData({
                piece: Cids.Cid(abi.encodePacked("test", i)),
                rawSize: 1024 * (i + 1)
            });
        }
        pdpVerifier.addPieces(setId, testPieces, empty);

        // Verify total count
        assertEq(pdpVerifier.getActivePieceCount(setId), 100, "Should have 100 active pieces");

        // Test pagination through the entire set
        uint256 totalRetrieved = 0;
        uint256 offset = 0;
        uint256 pageSize = 20;

        while (offset < 100) {
            (Cids.Cid[] memory pieces, uint256[] memory ids, uint256[] memory sizes, bool hasMore) =
                pdpVerifier.getActivePieces(setId, offset, pageSize);

            if (offset + pageSize < 100) {
                assertEq(hasMore, true, "Should have more pages");
                assertEq(pieces.length, pageSize, "Should return full page");
            } else {
                assertEq(hasMore, false, "Should not have more pages");
                assertEq(pieces.length, 100 - offset, "Should return remaining pieces");
            }

            // Verify IDs are sequential
            for (uint i = 0; i < pieces.length; i++) {
                assertEq(ids[i], offset + i, "IDs should be sequential");
                assertEq(sizes[i], 1024 * (offset + i + 1), "Sizes should match pattern");
            }

            totalRetrieved += pieces.length;
            offset += pageSize;
        }

        assertEq(totalRetrieved, 100, "Should have retrieved all 100 pieces");
    }
}

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

// TestingRecordKeeperService is a PDPListener that allows any amount of proof challenges
// to help with more flexible testing.
contract TestingRecordKeeperService is PDPListener, PDPRecordKeeper {
    // Implement the new storageProviderChanged hook
    /// @notice Called when data set storage provider role is changed in PDPVerifier.
    function storageProviderChanged(uint256, address, address, bytes calldata) external override {}

    function dataSetCreated(uint256 dataSetId, address creator, bytes calldata) external override {
        receiveDataSetEvent(dataSetId, PDPRecordKeeper.OperationType.CREATE, abi.encode(creator));
    }

    function dataSetDeleted(uint256 dataSetId, uint256 deletedLeafCount, bytes calldata) external override {
        receiveDataSetEvent(dataSetId, PDPRecordKeeper.OperationType.DELETE, abi.encode(deletedLeafCount));
    }

    function piecesAdded(uint256 dataSetId, uint256 firstAdded, IPDPTypes.PieceData[] calldata pieceData, bytes calldata) external override {
        receiveDataSetEvent(dataSetId, PDPRecordKeeper.OperationType.ADD, abi.encode(firstAdded, pieceData));
    }

    function piecesScheduledRemove(uint256 dataSetId, uint256[] calldata pieceIds, bytes calldata) external override {
        receiveDataSetEvent(dataSetId, PDPRecordKeeper.OperationType.REMOVE_SCHEDULED, abi.encode(pieceIds));
    }

    function possessionProven(uint256 dataSetId, uint256 challengedLeafCount, uint256 seed, uint256 challengeCount) external override {
        receiveDataSetEvent(dataSetId, PDPRecordKeeper.OperationType.PROVE_POSSESSION, abi.encode(challengedLeafCount, seed, challengeCount));
    }

    function nextProvingPeriod(uint256 dataSetId, uint256 challengeEpoch, uint256 leafCount, bytes calldata) external override {
        receiveDataSetEvent(dataSetId, PDPRecordKeeper.OperationType.NEXT_PROVING_PERIOD, abi.encode(challengeEpoch, leafCount));
    }
}

contract PDPVerifierProofTest is Test, ProofBuilderHelper {
    uint256 constant challengeFinalityDelay = 2;
    string constant cidPrefix = "CID";
    bytes empty = new bytes(0);
    PDPVerifier pdpVerifier;
    PDPListener listener;


    function setUp() public {
        PDPVerifier pdpVerifierImpl = new PDPVerifier();
        bytes memory initializeData = abi.encodeWithSelector(
            PDPVerifier.initialize.selector,
            challengeFinalityDelay
        );
        MyERC1967Proxy proxy = new MyERC1967Proxy(address(pdpVerifierImpl), initializeData);
        pdpVerifier = PDPVerifier(address(proxy));
        vm.fee(1 wei);
        vm.deal(address(pdpVerifierImpl), 100 ether);
    }

    function createPythCallData() internal view returns (bytes memory, PythStructs.Price memory) {
        bytes memory pythCallData = abi.encodeWithSelector(
            IPyth.getPriceNoOlderThan.selector,
            pdpVerifier.FIL_USD_PRICE_FEED_ID(),
            86400
        );

        PythStructs.Price memory price = PythStructs.Price({
            price: 5,
            conf: 0,
            expo: 0,
            publishTime: 0
        });

        return (pythCallData, price);
    }

    function testProveSinglePiece() public {
        // Mock Pyth oracle call to return $5 USD/FIL
        (bytes memory pythCallData, PythStructs.Price memory price) = createPythCallData();
        vm.mockCall(address(pdpVerifier.PYTH()), pythCallData, abi.encode(price));

        uint leafCount = 10;
        (uint256 setId, bytes32[][] memory tree) = makeDataSetWithOnePiece(leafCount);

        // Advance chain until challenge epoch.
        uint256 challengeEpoch = pdpVerifier.getNextChallengeEpoch(setId);
        vm.roll(challengeEpoch);

        // Build a proof with  multiple challenges to single tree.
        uint challengeCount = 3;
        IPDPTypes.Proof[] memory proofs = buildProofsForSingleton(setId, challengeCount, tree, leafCount);

        // Submit proof.
        vm.mockCall(pdpVerifier.RANDOMNESS_PRECOMPILE(), abi.encode(challengeEpoch), abi.encode(challengeEpoch));
        vm.expectEmit(true, true, false, false);
        IPDPTypes.PieceIdAndOffset[] memory challenges = new IPDPTypes.PieceIdAndOffset[](challengeCount);
        for (uint i = 0; i < challengeCount; i++) {
            challenges[i] = IPDPTypes.PieceIdAndOffset(0, 0);
        }
        emit IPDPEvents.PossessionProven(setId, challenges);
        pdpVerifier.provePossession{value: 1e18}(setId, proofs);


        // Verify the next challenge is in a subsequent epoch.
        // Next challenge unchanged by prove
        assertEq(pdpVerifier.getNextChallengeEpoch(setId), challengeEpoch);

        // Verify the next challenge is in a subsequent epoch after nextProvingPeriod
        pdpVerifier.nextProvingPeriod(setId, block.number + challengeFinalityDelay, empty);

        assertEq(pdpVerifier.getNextChallengeEpoch(setId), block.number + challengeFinalityDelay);
    }

    receive() external payable {}
        event Debug(string message, uint256 value);

    function testProveWithDifferentFeeAmounts() public {
        vm.fee(0 gwei);
        // Mock Pyth oracle call to return $5 USD/FIL
        (bytes memory pythCallData, PythStructs.Price memory price) = createPythCallData();
        price.price = 1;
        vm.mockCall(address(pdpVerifier.PYTH()), pythCallData, abi.encode(price));

        address sender = makeAddr("sender");
        vm.deal(sender, 1000 ether);
        vm.startPrank(sender);

        uint leafCount = 10;
        (uint256 setId, bytes32[][] memory tree) = makeDataSetWithOnePiece(leafCount);

        // Advance chain until challenge epoch.
        uint256 challengeEpoch = pdpVerifier.getNextChallengeEpoch(setId);
        vm.roll(challengeEpoch);

        vm.mockCall(pdpVerifier.RANDOMNESS_PRECOMPILE(), abi.encode(challengeEpoch), abi.encode(challengeEpoch));

        // Build a proof with multiple challenges to single tree.
        uint challengeCount = 3;
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
        vm.mockCall(pdpVerifier.RANDOMNESS_PRECOMPILE(), abi.encode(challengeEpoch), abi.encode(challengeEpoch));
        pdpVerifier.provePossession{value: correctFee + 1}(setId, proofs);

        // Verify that the proof was accepted
        assertEq(pdpVerifier.getNextChallengeEpoch(setId), challengeEpoch, "Next challenge epoch should remain unchanged after prove");
    }

    function testDataSetLastProvenEpochOnPieceRemoval() public {
        // Create a data set and verify initial lastProvenEpoch is 0
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);
        assertEq(pdpVerifier.getDataSetLastProvenEpoch(setId), 0, "Initial lastProvenEpoch should be 0");

        // Mock block.number to 2881
        uint256 blockNumber = 2881;
        vm.roll(blockNumber);
        // Add a piece and verify lastProvenEpoch is set to current block number
        IPDPTypes.PieceData[] memory pieces = new IPDPTypes.PieceData[](1);
        pieces[0] = IPDPTypes.PieceData(Cids.Cid(abi.encodePacked("test")), 64);


        pdpVerifier.addPieces(setId, pieces, empty);
        pdpVerifier.nextProvingPeriod(setId, blockNumber + challengeFinalityDelay, empty);
        assertEq(pdpVerifier.getDataSetLastProvenEpoch(setId), blockNumber, "lastProvenEpoch should be set to block.number after first proving period piece");

        // Schedule piece removal
        uint256[] memory piecesToRemove = new uint256[](1);
        piecesToRemove[0] = 0;
        pdpVerifier.schedulePieceDeletions(setId, piecesToRemove, empty);


        // Call nextProvingPeriod and verify lastProvenEpoch is reset to 0
        pdpVerifier.nextProvingPeriod(setId, blockNumber + challengeFinalityDelay, empty);
        assertEq(pdpVerifier.getDataSetLastProvenEpoch(setId), 0, "lastProvenEpoch should be reset to 0 after removing last piece");
    }

    function testLateProofAccepted() public {
        // Mock Pyth oracle call to return $5 USD/FIL
        (bytes memory pythCallData, PythStructs.Price memory price) = createPythCallData();
        vm.mockCall(address(pdpVerifier.PYTH()), pythCallData, abi.encode(price));

        uint leafCount = 10;
        (uint256 setId, bytes32[][] memory tree) = makeDataSetWithOnePiece(leafCount);

        // Advance chain short of challenge epoch
        uint256 challengeEpoch = pdpVerifier.getNextChallengeEpoch(setId);
        vm.roll(challengeEpoch + 100);

        // Build a proof.
        IPDPTypes.Proof[] memory proofs = buildProofsForSingleton(setId, 3, tree, leafCount);

        // Submit proof.
        vm.mockCall(pdpVerifier.RANDOMNESS_PRECOMPILE(), abi.encode(challengeEpoch), abi.encode(challengeEpoch));
        pdpVerifier.provePossession{value: 1e18}(setId, proofs);
    }

    function testEarlyProofRejected() public {
        uint leafCount = 10;
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
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);
        IPDPTypes.PieceData[] memory pieces = new IPDPTypes.PieceData[](1);
        pieces[0] = IPDPTypes.PieceData(Cids.Cid(abi.encodePacked("test")), 64);
        pdpVerifier.addPieces(setId, pieces, empty);

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
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);
        IPDPTypes.Proof[] memory emptyProof = new IPDPTypes.Proof[](0);

        // Rejected with no pieces
        vm.expectRevert();
        pdpVerifier.provePossession{value:1e18}(setId, emptyProof);

        addOnePiece(setId, 10);

        // Rejected with a piece
        vm.expectRevert();
        pdpVerifier.provePossession{value: 1e18}(setId, emptyProof);
    }

    function testBadChallengeRejected() public {
        uint leafCount = 10;
        (uint256 setId, bytes32[][] memory tree) = makeDataSetWithOnePiece(leafCount);

        // Make a proof that's good for this challenge epoch.
        uint256 challengeEpoch = pdpVerifier.getNextChallengeEpoch(setId);
        vm.roll(challengeEpoch);
        IPDPTypes.Proof[] memory proofs = buildProofsForSingleton(setId, 3, tree, leafCount);

        // Submit proof successfully, advancing the data set to a new challenge epoch.
        vm.mockCall(pdpVerifier.RANDOMNESS_PRECOMPILE(), abi.encode(challengeEpoch), abi.encode(challengeEpoch));
        // Mock Pyth oracle call to return $5 USD/FIL
        (bytes memory pythCallData, PythStructs.Price memory price) = createPythCallData();
        vm.mockCall(address(pdpVerifier.PYTH()), pythCallData, abi.encode(price));

        pdpVerifier.provePossession{value: 1e18}(setId, proofs);
        pdpVerifier.nextProvingPeriod(setId, block.number + challengeFinalityDelay, empty); // resample

        uint nextChallengeEpoch = pdpVerifier.getNextChallengeEpoch(setId);
        assertNotEq(nextChallengeEpoch, challengeEpoch);
        vm.roll(nextChallengeEpoch);

        // The proof for the old challenge epoch should no longer be valid.
        vm.expectRevert();
        pdpVerifier.provePossession{value: 1e18}(setId, proofs);
    }

    function testBadPiecesRejected() public {
        // Mock Pyth oracle call to return $5 USD/FIL
        (bytes memory pythCallData, PythStructs.Price memory price) = createPythCallData();
        vm.mockCall(address(pdpVerifier.PYTH()), pythCallData, abi.encode(price));

        uint[] memory leafCounts = new uint[](2);
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
        vm.mockCall(pdpVerifier.RANDOMNESS_PRECOMPILE(), abi.encode(challengeEpoch), abi.encode(challengeEpoch));
        vm.expectRevert();
        pdpVerifier.provePossession{value: 1e18}(setId, proofsOneRoot);

        // Remove a piece and resample
        uint256[] memory removePieces = new uint256[](1);
        removePieces[0] = newPieceId;
        pdpVerifier.schedulePieceDeletions(setId, removePieces, empty);
        // flush removes
        pdpVerifier.nextProvingPeriod(setId, block.number + challengeFinalityDelay, empty);

        // Make a new proof that is valid with two pieces
        challengeEpoch = pdpVerifier.getNextChallengeEpoch(setId);
        vm.roll(challengeEpoch);
        IPDPTypes.Proof[] memory proofsTwoRoots = buildProofs(pdpVerifier, setId, 10, trees, leafCounts);

        // A proof for two pieces should be invalid against the set with one.
        proofsTwoRoots = buildProofs(pdpVerifier, setId, 10, trees, leafCounts); // regen as removal forced resampling challenge seed
        vm.mockCall(pdpVerifier.RANDOMNESS_PRECOMPILE(), abi.encode(challengeEpoch), abi.encode(challengeEpoch));
        vm.expectRevert();
        pdpVerifier.provePossession{value: 1e18}(setId, proofsTwoRoots);

        // But the single piece proof is now good again.
        proofsOneRoot = buildProofsForSingleton(setId, 1, trees[0], leafCounts[0]); // regen as removal forced resampling challenge seed
        vm.mockCall(pdpVerifier.RANDOMNESS_PRECOMPILE(), abi.encode(challengeEpoch), abi.encode(challengeEpoch));
        pdpVerifier.provePossession{value: 1e18}(setId, proofsOneRoot);
    }

    function testProveManyPieces() public {
        // Mock Pyth oracle call to return $5 USD/FIL
        (bytes memory pythCallData, PythStructs.Price memory price) = createPythCallData();
        vm.mockCall(address(pdpVerifier.PYTH()), pythCallData, abi.encode(price));

        uint[] memory leafCounts = new uint[](3);
        // Pick a distinct size for each tree (up to some small maximum size).
        for (uint i = 0; i < leafCounts.length; i++) {
            leafCounts[i] = uint256(sha256(abi.encode(i))) % 64;
        }

        (uint256 setId, bytes32[][][] memory trees) = makeDataSetWithPieces(leafCounts);

        // Advance chain until challenge epoch.
        uint256 challengeEpoch = pdpVerifier.getNextChallengeEpoch(setId);
        vm.roll(challengeEpoch);

        // Build a proof with multiple challenges to span the pieces.
        uint challengeCount = 11;
        IPDPTypes.Proof[] memory proofs = buildProofs(pdpVerifier, setId, challengeCount, trees, leafCounts);
        // Submit proof.
        vm.mockCall(pdpVerifier.RANDOMNESS_PRECOMPILE(), abi.encode(challengeEpoch), abi.encode(challengeEpoch));
        pdpVerifier.provePossession{value: 1e18}(setId, proofs);
    }

    function testNextProvingPeriodFlexibleScheduling() public {
        // Mock Pyth oracle call to return $5 USD/FIL
        (bytes memory pythCallData, PythStructs.Price memory price) = createPythCallData();
        vm.mockCall(address(pdpVerifier.PYTH()), pythCallData, abi.encode(price));

        // Create data set and add initial piece
        uint leafCount = 10;
        (uint256 setId, bytes32[][] memory tree) = makeDataSetWithOnePiece(leafCount);

        // Set challenge sampling far in the future
        uint256 farFutureBlock = block.number + 1000;
        pdpVerifier.nextProvingPeriod(setId, farFutureBlock, empty);
        assertEq(pdpVerifier.getNextChallengeEpoch(setId), farFutureBlock, "Challenge epoch should be set to far future");

        // Reset to a closer block
        uint256 nearerBlock = block.number + challengeFinalityDelay;
        pdpVerifier.nextProvingPeriod(setId, nearerBlock, empty);
        assertEq(pdpVerifier.getNextChallengeEpoch(setId), nearerBlock, "Challenge epoch should be reset to nearer block");

        // Verify we can still prove possession at the new block
        vm.roll(nearerBlock);

        IPDPTypes.Proof[] memory proofs = buildProofsForSingleton(setId, 5, tree, 10);
        vm.mockCall(pdpVerifier.RANDOMNESS_PRECOMPILE(), abi.encode(pdpVerifier.getNextChallengeEpoch(setId)), abi.encode(pdpVerifier.getNextChallengeEpoch(setId)));
        pdpVerifier.provePossession{value: 1e18}(setId, proofs);
    }


    function testProveSingleFake() public {
        // Mock Pyth oracle call to return $5 USD/FIL
        (bytes memory pythCallData, PythStructs.Price memory price) = createPythCallData();
        vm.mockCall(address(pdpVerifier.PYTH()), pythCallData, abi.encode(price));

        uint leafCount = 10;
        (uint256 setId, bytes32[][] memory tree) = makeDataSetWithOnePiece(leafCount);

        // Advance chain until challenge epoch.
        uint256 challengeEpoch = pdpVerifier.getNextChallengeEpoch(setId);
        vm.roll(challengeEpoch);

        uint challengeCount = 3;
        // build fake proofs
        IPDPTypes.Proof[] memory proofs = new IPDPTypes.Proof[](5);
        for (uint i = 0; i < 5; i++) {
            proofs[i] = IPDPTypes.Proof(tree[0][0], new bytes32[](0));
        }

        // Submit proof.
        vm.mockCall(pdpVerifier.RANDOMNESS_PRECOMPILE(), abi.encode(challengeEpoch), abi.encode(challengeEpoch));
        IPDPTypes.PieceIdAndOffset[] memory challenges = new IPDPTypes.PieceIdAndOffset[](challengeCount);
        for (uint i = 0; i < challengeCount; i++) {
            challenges[i] = IPDPTypes.PieceIdAndOffset(0, 0);
        }
        vm.expectRevert("proof length does not match tree height");
        pdpVerifier.provePossession{value: 1e18}(setId, proofs);
    }

    ///// Helpers /////

    // Initializes a new data set, generates trees of specified sizes, and adds pieces to the set.
    function makeDataSetWithPieces(uint[] memory leafCounts) internal returns (uint256, bytes32[][][]memory) {
        // Create trees and their pieces.
        bytes32[][][] memory trees = new bytes32[][][](leafCounts.length);
        IPDPTypes.PieceData[] memory pieces = new IPDPTypes.PieceData[](leafCounts.length);
        for (uint i = 0; i < leafCounts.length; i++) {
            // Generate a uniquely-sized tree for each piece (up to some small maximum size).
            trees[i] = ProofUtil.makeTree(leafCounts[i]);
            pieces[i] = makePiece(trees[i], leafCounts[i]);
        }

        // Create new data set and add pieces.
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);
        pdpVerifier.addPieces(setId, pieces, empty);
        pdpVerifier.nextProvingPeriod(setId, block.number + challengeFinalityDelay, empty); // flush adds
        return (setId, trees);
    }

    // Initializes a new data set and adds a single generated tree.
    function makeDataSetWithOnePiece(uint leafCount) internal returns (uint256, bytes32[][]memory) {
         uint[] memory leafCounts = new uint[](1);
        leafCounts[0] = leafCount;
        (uint256 setId, bytes32[][][] memory trees) = makeDataSetWithPieces(leafCounts);
        return (setId, trees[0]);
    }

    // Creates a tree and adds it to a data set.
    // Returns the Merkle tree and piece.
    function addOnePiece(uint256 setId, uint leafCount) internal returns (bytes32[][] memory, uint256) {
        bytes32[][] memory tree = ProofUtil.makeTree(leafCount);
        IPDPTypes.PieceData[] memory pieces = new IPDPTypes.PieceData[](1);
        pieces[0] = makePiece(tree, leafCount);
        uint256 pieceId = pdpVerifier.addPieces(setId, pieces, empty);
        pdpVerifier.nextProvingPeriod(setId, block.number + challengeFinalityDelay, empty); // flush adds
        return (tree, pieceId);
    }

    // Builds a proof of posesesion for a data set with a single piece.
    function buildProofsForSingleton(uint256 setId, uint challengeCount, bytes32[][] memory tree, uint leafCount) internal view returns (IPDPTypes.Proof[] memory) {
        bytes32[][][] memory trees = new bytes32[][][](1);
        trees[0] = tree;
        uint[] memory leafCounts = new uint[](1);
        leafCounts[0] = leafCount;
        IPDPTypes.Proof[] memory proofs = buildProofs(pdpVerifier, setId, challengeCount, trees, leafCounts);
        return proofs;
    }
}

// Constructs a PieceData structure for a Merkle tree.
function makePiece(bytes32[][] memory tree, uint leafCount) pure returns (IPDPTypes.PieceData memory) {
    // height is log2 of leaf count, use clz
    uint8 height = uint8(256 - BitOps.clz(leafCount - 1) + 1);
    uint256 paddingLeafs = 1<<height - leafCount;
    return IPDPTypes.PieceData(Cids.commpV2FromDigest( height, tree[0][0]), leafCount * 32);
}

function makeSamplePiece(uint leafCount) pure returns (IPDPTypes.PieceData memory) {
    bytes32[][] memory tree = ProofUtil.makeTree(leafCount);
    return makePiece(tree, leafCount);
}




contract SumTreeInternalTestPDPVerifier is PDPVerifier {
    constructor() {
    }
    function getTestHeightFromIndex(uint256 index) public pure returns (uint256) {
        return heightFromIndex(index);
    }

    function getSumTreeCounts(uint256 setId, uint256 pieceId) public view returns (uint256) {
        return sumTreeCounts[setId][pieceId];
    }
}

contract SumTreeHeightTest is Test {
    SumTreeInternalTestPDPVerifier pdpVerifier;

    function setUp() public {
        PDPVerifier pdpVerifierImpl = new SumTreeInternalTestPDPVerifier();
        bytes memory initializeData = abi.encodeWithSelector(
            PDPVerifier.initialize.selector,
            2
        );
        MyERC1967Proxy proxy = new MyERC1967Proxy(address(pdpVerifierImpl), initializeData);
        pdpVerifier = SumTreeInternalTestPDPVerifier(address(proxy));
    }

    function testHeightFromIndex() public view {
        // https://oeis.org/A001511
        uint8[105] memory oeisA001511 = [
            1, 2, 1, 3, 1, 2, 1, 4, 1, 2, 1, 3, 1, 2, 1, 5, 1, 2, 1, 3, 1, 2, 1, 4, 1, 2, 1, 3, 1, 2, 1, 6,
            1, 2, 1, 3, 1, 2, 1, 4, 1, 2, 1, 3, 1, 2, 1, 5, 1, 2, 1, 3, 1, 2, 1, 4, 1, 2, 1, 3, 1, 2, 1, 7,
            1, 2, 1, 3, 1, 2, 1, 4, 1, 2, 1, 3, 1, 2, 1, 5, 1, 2, 1, 3, 1, 2, 1, 4, 1, 2, 1, 3, 1, 2, 1, 6,
            1, 2, 1, 3, 1, 2, 1, 4, 1
        ];
        for (uint256 i = 0; i < 105; i++) {
            assertEq(uint256(oeisA001511[i]), pdpVerifier.getTestHeightFromIndex(i) + 1, "Heights from index 0 to 104 should match OEIS A001511");
        }
    }
}

import "forge-std/Test.sol";
import "../src/PDPVerifier.sol";

contract SumTreeAddTest is Test {
    SumTreeInternalTestPDPVerifier pdpVerifier;
    TestingRecordKeeperService listener;
    uint256 testSetId;
    uint256 challengeFinalityDelay = 100;
    bytes empty = new bytes(0);

    function setUp() public {
        PDPVerifier pdpVerifierImpl = new SumTreeInternalTestPDPVerifier();
        bytes memory initializeData = abi.encodeWithSelector(
            PDPVerifier.initialize.selector,
            challengeFinalityDelay
        );
        MyERC1967Proxy proxy = new MyERC1967Proxy(address(pdpVerifierImpl), initializeData);
        pdpVerifier = SumTreeInternalTestPDPVerifier(address(proxy));
        listener = new TestingRecordKeeperService();
        testSetId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);
    }

    function testMultiAdd() public {
        uint256[] memory counts = new uint256[](8);
        counts[0] = 1;
        counts[1] = 2;
        counts[2] = 3;
        counts[3] = 5;
        counts[4] = 8;
        counts[5] = 13;
        counts[6] = 21;
        counts[7] = 34;

        IPDPTypes.PieceData[] memory pieceDataArray = new IPDPTypes.PieceData[](8);

        for (uint256 i = 0; i < counts.length; i++) {
            Cids.Cid memory testCid = Cids.Cid(abi.encodePacked("test", i));
            pieceDataArray[i] = IPDPTypes.PieceData(testCid, counts[i] * pdpVerifier.LEAF_SIZE());
        }
        pdpVerifier.addPieces(testSetId, pieceDataArray, empty);
        assertEq(pdpVerifier.getDataSetLeafCount(testSetId), 87, "Incorrect final data set leaf count");
        assertEq(pdpVerifier.getNextPieceId(testSetId), 8, "Incorrect next piece ID");
        assertEq(pdpVerifier.getSumTreeCounts(testSetId, 7), 87, "Incorrect sum tree count");
        assertEq(pdpVerifier.getPieceLeafCount(testSetId, 7), 34, "Incorrect piece leaf count");
        Cids.Cid memory expectedCid = Cids.Cid(abi.encodePacked("test", uint256(3)));
        Cids.Cid memory actualCid = pdpVerifier.getPieceCid(testSetId, 3);
        assertEq(actualCid.data, expectedCid.data, "Incorrect piece CID");
    }

    function setUpTestingArray() public returns (uint256[] memory counts, uint256[] memory expectedSumTreeCounts) {
        counts = new uint256[](8);
        counts[0] = 200;
        counts[1] = 100;
        counts[2] = 1; // Remove
        counts[3] = 30;
        counts[4] = 50;
        counts[5] = 1; // Remove
        counts[6] = 400;
        counts[7] = 40;

        // Correct sum tree values assuming that pieceIdsToRemove are deleted
        expectedSumTreeCounts = new uint256[](8);
        expectedSumTreeCounts[0] = 200;
        expectedSumTreeCounts[1] = 300;
        expectedSumTreeCounts[2] = 0;
        expectedSumTreeCounts[3] = 330;
        expectedSumTreeCounts[4] = 50;
        expectedSumTreeCounts[5] = 50;
        expectedSumTreeCounts[6] = 400;
        expectedSumTreeCounts[7] = 820;

        uint256[] memory pieceIdsToRemove = new uint256[](2);
        pieceIdsToRemove[0] = 2;
        pieceIdsToRemove[1] = 5;

        // Add all
        for (uint256 i = 0; i < counts.length; i++) {
            Cids.Cid memory testCid = Cids.Cid(abi.encodePacked("test", i));
            IPDPTypes.PieceData[] memory pieceDataArray = new IPDPTypes.PieceData[](1);
            pieceDataArray[0] = IPDPTypes.PieceData(testCid, counts[i] * pdpVerifier.LEAF_SIZE());
            pdpVerifier.addPieces(testSetId, pieceDataArray, empty);
            // Assert the piece was added correctly
            assertEq(pdpVerifier.getPieceCid(testSetId, i).data, testCid.data, "Piece not added correctly");
        }

        // Delete some
        // Remove pieces in batch
        pdpVerifier.schedulePieceDeletions(testSetId, pieceIdsToRemove, empty);
        // flush adds and removals
        pdpVerifier.nextProvingPeriod(testSetId, block.number + challengeFinalityDelay, empty);
        for (uint256 i = 0; i < pieceIdsToRemove.length; i++) {
            bytes memory zeroBytes;
            assertEq(pdpVerifier.getPieceCid(testSetId, pieceIdsToRemove[i]).data, zeroBytes);
            assertEq(pdpVerifier.getPieceLeafCount(testSetId, pieceIdsToRemove[i]), 0, "Piece size should be 0");
        }
    }

    function testSumTree() public {
        (uint256[] memory counts, uint256[] memory expectedSumTreeCounts) = setUpTestingArray();
        // Assert that the sum tree count is correct
        for (uint256 i = 0; i < counts.length; i++) {
            assertEq(pdpVerifier.getSumTreeCounts(testSetId, i), expectedSumTreeCounts[i], "Incorrect sum tree size");
        }

        // Assert final data set leaf count
        assertEq(pdpVerifier.getDataSetLeafCount(testSetId), 820, "Incorrect final data set leaf count");
    }

    function testFindPieceId() public {
        setUpTestingArray();

        // Test findPieceId for various positions
        assertFindPieceAndOffset(testSetId, 0, 0, 0);
        assertFindPieceAndOffset(testSetId, 199, 0, 199);
        assertFindPieceAndOffset(testSetId, 200, 1, 0);
        assertFindPieceAndOffset(testSetId, 299, 1, 99);
        assertFindPieceAndOffset(testSetId, 300, 3, 0);
        assertFindPieceAndOffset(testSetId, 329, 3, 29);
        assertFindPieceAndOffset(testSetId, 330, 4, 0);
        assertFindPieceAndOffset(testSetId, 379, 4, 49);
        assertFindPieceAndOffset(testSetId, 380, 6, 0);
        assertFindPieceAndOffset(testSetId, 779, 6, 399);
        assertFindPieceAndOffset(testSetId, 780, 7, 0);
        assertFindPieceAndOffset(testSetId, 819, 7, 39);

        // Test edge cases
        vm.expectRevert("Leaf index out of bounds");
        uint256[] memory outOfBounds = new uint256[](1);
        outOfBounds[0] = 820;
        pdpVerifier.findPieceIds(testSetId, outOfBounds);

        vm.expectRevert("Leaf index out of bounds");
        outOfBounds[0] = 1000;
        pdpVerifier.findPieceIds(testSetId, outOfBounds);
    }

    function testBatchFindPieceId() public {
        setUpTestingArray();
        uint256[] memory searchIndexes = new uint256[](12);
        searchIndexes[0] = 0;
        searchIndexes[1] = 199;
        searchIndexes[2] = 200;
        searchIndexes[3] = 299;
        searchIndexes[4] = 300;
        searchIndexes[5] = 329;
        searchIndexes[6] = 330;
        searchIndexes[7] = 379;
        searchIndexes[8] = 380;
        searchIndexes[9] = 779;
        searchIndexes[10] = 780;
        searchIndexes[11] = 819;

        uint256[] memory expectedPieces = new uint256[](12);
        expectedPieces[0] = 0;
        expectedPieces[1] = 0;
        expectedPieces[2] = 1;
        expectedPieces[3] = 1;
        expectedPieces[4] = 3;
        expectedPieces[5] = 3;
        expectedPieces[6] = 4;
        expectedPieces[7] = 4;
        expectedPieces[8] = 6;
        expectedPieces[9] = 6;
        expectedPieces[10] = 7;
        expectedPieces[11] = 7;

        uint256[] memory expectedOffsets = new uint256[](12);
        expectedOffsets[0] = 0;
        expectedOffsets[1] = 199;
        expectedOffsets[2] = 0;
        expectedOffsets[3] = 99;
        expectedOffsets[4] = 0;
        expectedOffsets[5] = 29;
        expectedOffsets[6] = 0;
        expectedOffsets[7] = 49;
        expectedOffsets[8] = 0;
        expectedOffsets[9] = 399;
        expectedOffsets[10] = 0;
        expectedOffsets[11] = 39;

        assertFindPiecesAndOffsets(testSetId, searchIndexes, expectedPieces, expectedOffsets);
    }

    error TestingFindError(uint256 expected, uint256 actual, string msg);

    function assertFindPieceAndOffset(uint256 setId, uint256 searchIndex, uint256 expectPieceId, uint256 expectOffset) internal view {
        uint256[] memory searchIndices = new uint256[](1);
        searchIndices[0] = searchIndex;
        IPDPTypes.PieceIdAndOffset[] memory result = pdpVerifier.findPieceIds(setId, searchIndices);
        if (result[0].pieceId != expectPieceId) {
            revert TestingFindError(expectPieceId, result[0].pieceId, "unexpected piece");
        }
        if (result[0].offset != expectOffset) {
            revert TestingFindError(expectOffset, result[0].offset, "unexpected offset");
        }
    }

    // The batched version of assertFindPieceAndOffset
    function assertFindPiecesAndOffsets(uint256 setId, uint256[] memory searchIndices, uint256[] memory expectPieceIds, uint256[] memory expectOffsets) internal view {
        IPDPTypes.PieceIdAndOffset[] memory result = pdpVerifier.findPieceIds(setId, searchIndices);
        for (uint256 i = 0; i < searchIndices.length; i++) {
            assertEq(result[i].pieceId, expectPieceIds[i], "unexpected piece");
            assertEq(result[i].offset, expectOffsets[i], "unexpected offset");
        }
    }

    function testFindPieceIdTraverseOffTheEdgeAndBack() public {
        uint256[] memory sizes = new uint256[](5);
        sizes[0] = 1; // Remove
        sizes[1] = 1; // Remove
        sizes[2] = 1; // Remove
        sizes[3] = 1;
        sizes[4] = 1;

        uint256[] memory pieceIdsToRemove = new uint256[](3);
        pieceIdsToRemove[0] = 0;
        pieceIdsToRemove[1] = 1;
        pieceIdsToRemove[2] = 2;

        for (uint256 i = 0; i < sizes.length; i++) {
            Cids.Cid memory testCid = Cids.Cid(abi.encodePacked("test", i));
            IPDPTypes.PieceData[] memory pieceDataArray = new IPDPTypes.PieceData[](1);
            pieceDataArray[0] = IPDPTypes.PieceData(testCid, sizes[i] * pdpVerifier.LEAF_SIZE());
            pdpVerifier.addPieces(testSetId, pieceDataArray, empty);
        }
        pdpVerifier.schedulePieceDeletions(testSetId, pieceIdsToRemove, empty);
        pdpVerifier.nextProvingPeriod(testSetId, block.number + challengeFinalityDelay, empty); //flush removals

        assertFindPieceAndOffset(testSetId, 0, 3, 0);
        assertFindPieceAndOffset(testSetId, 1, 4, 0);
    }
}

contract BadListener is PDPListener {
    PDPRecordKeeper.OperationType public badOperation;

    function setBadOperation(PDPRecordKeeper.OperationType operationType) external {
        badOperation = operationType;
    }

    function storageProviderChanged(uint256, address, address, bytes calldata) external override {}

    function dataSetCreated(uint256 dataSetId, address creator, bytes calldata) external override view {
        receiveDataSetEvent(dataSetId, PDPRecordKeeper.OperationType.CREATE, abi.encode(creator));
    }

    function dataSetDeleted(uint256 dataSetId, uint256 deletedLeafCount, bytes calldata) external override view {
        receiveDataSetEvent(dataSetId, PDPRecordKeeper.OperationType.DELETE, abi.encode(deletedLeafCount));
    }

    function piecesAdded(uint256 dataSetId, uint256 firstAdded, IPDPTypes.PieceData[] calldata pieceData, bytes calldata) external override view {
        receiveDataSetEvent(dataSetId, PDPRecordKeeper.OperationType.ADD, abi.encode(firstAdded, pieceData));
    }
    function piecesScheduledRemove(uint256 dataSetId, uint256[] calldata pieceIds, bytes calldata) external override view {
        receiveDataSetEvent(dataSetId, PDPRecordKeeper.OperationType.REMOVE_SCHEDULED, abi.encode(pieceIds));
    }

    function possessionProven(uint256 dataSetId, uint256 challengedLeafCount, uint256 seed, uint256 challengeCount) external override view {
        receiveDataSetEvent(dataSetId, PDPRecordKeeper.OperationType.PROVE_POSSESSION, abi.encode(challengedLeafCount, seed, challengeCount));
    }

    function nextProvingPeriod(uint256 dataSetId, uint256 challengeEpoch, uint256 leafCount, bytes calldata) external override view {
        receiveDataSetEvent(dataSetId, PDPRecordKeeper.OperationType.NEXT_PROVING_PERIOD, abi.encode(challengeEpoch, leafCount));
    }

    function receiveDataSetEvent(
        uint256,
        PDPRecordKeeper.OperationType operationType,
        bytes memory
    ) view internal {
        if (operationType == badOperation) {
            revert("Failing operation");
        }
    }
}

contract PDPListenerIntegrationTest is Test {
    PDPVerifier pdpVerifier;
    BadListener badListener;
    uint256 constant challengeFinalityDelay = 2;
    bytes empty = new bytes(0);

    function setUp() public {
        PDPVerifier pdpVerifierImpl = new PDPVerifier();
        bytes memory initializeData = abi.encodeWithSelector(
            PDPVerifier.initialize.selector,
            challengeFinalityDelay
        );
        MyERC1967Proxy proxy = new MyERC1967Proxy(address(pdpVerifierImpl), initializeData);
        pdpVerifier = PDPVerifier(address(proxy));
        badListener = new BadListener();
    }

    function testListenerPropagatesErrors() public {
        badListener.setBadOperation(PDPRecordKeeper.OperationType.CREATE);
        vm.expectRevert("Failing operation");
        pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(badListener), empty);

        badListener.setBadOperation(PDPRecordKeeper.OperationType.NONE);
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(badListener), empty);

        badListener.setBadOperation(PDPRecordKeeper.OperationType.ADD);
        IPDPTypes.PieceData[] memory pieces = new IPDPTypes.PieceData[](1);
        pieces[0] = IPDPTypes.PieceData(Cids.Cid(abi.encodePacked("test")), 32);
        vm.expectRevert("Failing operation");
        pdpVerifier.addPieces(setId, pieces, empty);

        badListener.setBadOperation(PDPRecordKeeper.OperationType.NONE);
        pdpVerifier.addPieces(setId, pieces, empty);

        badListener.setBadOperation(PDPRecordKeeper.OperationType.REMOVE_SCHEDULED);
        uint256[] memory pieceIds = new uint256[](1);
        pieceIds[0] = 0;
        vm.expectRevert("Failing operation");
        pdpVerifier.schedulePieceDeletions(setId, pieceIds, empty);

        badListener.setBadOperation(PDPRecordKeeper.OperationType.NONE);
        pdpVerifier.schedulePieceDeletions(setId, pieceIds, empty);

        badListener.setBadOperation(PDPRecordKeeper.OperationType.NEXT_PROVING_PERIOD);
        vm.expectRevert("Failing operation");
        pdpVerifier.nextProvingPeriod(setId, block.number + challengeFinalityDelay, empty);

        badListener.setBadOperation(PDPRecordKeeper.OperationType.NONE);
        pdpVerifier.nextProvingPeriod(setId, block.number + challengeFinalityDelay, empty);
    }
}

contract ExtraDataListener is PDPListener {
    mapping(uint256 => mapping(PDPRecordKeeper.OperationType => bytes)) public extraDataBySetId;

    function storageProviderChanged(uint256, address, address, bytes calldata) external override {}
    function dataSetCreated(uint256 dataSetId, address, bytes calldata extraData) external override {
        extraDataBySetId[dataSetId][PDPRecordKeeper.OperationType.CREATE] = extraData;
    }
    function dataSetDeleted(uint256 dataSetId, uint256, bytes calldata extraData) external override {
        extraDataBySetId[dataSetId][PDPRecordKeeper.OperationType.DELETE] = extraData;
    }
    function piecesAdded(uint256 dataSetId, uint256, IPDPTypes.PieceData[] calldata, bytes calldata extraData) external override {
        extraDataBySetId[dataSetId][PDPRecordKeeper.OperationType.ADD] = extraData;
    }
    function piecesScheduledRemove(uint256 dataSetId, uint256[] calldata, bytes calldata extraData) external override {
        extraDataBySetId[dataSetId][PDPRecordKeeper.OperationType.REMOVE_SCHEDULED] = extraData;
    }
    function possessionProven(uint256, uint256, uint256, uint256) external override {}
    function nextProvingPeriod(uint256 dataSetId, uint256, uint256, bytes calldata extraData) external override {
        extraDataBySetId[dataSetId][PDPRecordKeeper.OperationType.NEXT_PROVING_PERIOD] = extraData;
    }
    function getExtraData(uint256 dataSetId, PDPRecordKeeper.OperationType opType) external view returns (bytes memory) {
        return extraDataBySetId[dataSetId][opType];
    }
}

contract PDPVerifierExtraDataTest is Test {
    PDPVerifier pdpVerifier;
    ExtraDataListener extraDataListener;
    uint256 constant challengeFinalityDelay = 2;
    bytes empty = new bytes(0);

    function setUp() public {
        PDPVerifier pdpVerifierImpl = new PDPVerifier();
        bytes memory initializeData = abi.encodeWithSelector(
            PDPVerifier.initialize.selector,
            challengeFinalityDelay
        );
        MyERC1967Proxy proxy = new MyERC1967Proxy(address(pdpVerifierImpl), initializeData);
        pdpVerifier = PDPVerifier(address(proxy));
        extraDataListener = new ExtraDataListener();
    }

    function testExtraDataPropagation() public {
        // Test CREATE operation
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(extraDataListener), empty);
        assertEq(
            extraDataListener.getExtraData(setId, PDPRecordKeeper.OperationType.CREATE),
            empty,
            "Extra data not propagated for CREATE"
        );

        // Test ADD operation
        IPDPTypes.PieceData[] memory pieces = new IPDPTypes.PieceData[](1);
        pieces[0] = IPDPTypes.PieceData(Cids.Cid(abi.encodePacked("test")), 32);
        pdpVerifier.addPieces(setId, pieces, empty);
        assertEq(
            extraDataListener.getExtraData(setId, PDPRecordKeeper.OperationType.ADD),
            empty,
            "Extra data not propagated for ADD"
        );

        // Test REMOVE_SCHEDULED operation
        uint256[] memory pieceIds = new uint256[](1);
        pieceIds[0] = 0;
        pdpVerifier.schedulePieceDeletions(setId, pieceIds, empty);
        assertEq(
            extraDataListener.getExtraData(setId, PDPRecordKeeper.OperationType.REMOVE_SCHEDULED),
            empty,
            "Extra data not propagated for REMOVE_SCHEDULED"
        );

        // Test NEXT_PROVING_PERIOD operation
        pdpVerifier.nextProvingPeriod(setId, block.number + challengeFinalityDelay, empty);
        assertEq(
            extraDataListener.getExtraData(setId, PDPRecordKeeper.OperationType.NEXT_PROVING_PERIOD),
            empty,
            "Extra data not propagated for NEXT_PROVING_PERIOD"
        );
    }
}

contract PDPVerifierE2ETest is Test, ProofBuilderHelper {
    PDPVerifier pdpVerifier;
    TestingRecordKeeperService listener;
    uint256 constant challengeFinalityDelay = 2;
    bytes empty = new bytes(0);

    function setUp() public {
        PDPVerifier pdpVerifierImpl = new PDPVerifier();
        bytes memory initializeData = abi.encodeWithSelector(
            PDPVerifier.initialize.selector,
            challengeFinalityDelay
        );
        MyERC1967Proxy proxy = new MyERC1967Proxy(address(pdpVerifierImpl), initializeData);
        pdpVerifier = PDPVerifier(address(proxy));
        listener = new TestingRecordKeeperService();
        vm.fee(1 gwei);
        vm.deal(address(pdpVerifierImpl), 100 ether);
    }

    receive() external payable {}

    function createPythCallData() internal view returns (bytes memory, PythStructs.Price memory) {
        bytes memory pythCallData = abi.encodeWithSelector(
            IPyth.getPriceNoOlderThan.selector,
            pdpVerifier.FIL_USD_PRICE_FEED_ID(),
            86400
        );

        PythStructs.Price memory price = PythStructs.Price({
            price: 5,
            conf: 0,
            expo: 0,
            publishTime: 0
        });

        return (pythCallData, price);
    }

    function createPythUnsafeCallData() internal view returns (bytes memory, PythStructs.Price memory) {
        bytes memory callData = abi.encodeWithSelector(
            IPyth.getPriceUnsafe.selector,
            pdpVerifier.FIL_USD_PRICE_FEED_ID()
        );

        PythStructs.Price memory price = PythStructs.Price({
            price: 6,
            conf: 0,
            expo: 0,
            publishTime: 0
        });

        return (callData, price);
    }

    function testGetPriceOracleFailure() public {
        (bytes memory pythCallData, PythStructs.Price memory _notReturnedPrice) = createPythCallData();
        bytes memory errorData = abi.encodeWithSelector(bytes4(keccak256("StalePrice()")));
        vm.mockCallRevert(address(pdpVerifier.PYTH()), pythCallData, errorData);
        (bytes memory pythFallbackCallData, PythStructs.Price memory price) = createPythUnsafeCallData();
        vm.mockCall(address(pdpVerifier.PYTH()), pythFallbackCallData, abi.encode(price));

        vm.expectEmit(true, false, false, false);
        emit IPDPEvents.PriceOracleFailure(errorData);

        (uint64 priceOut, int32 expoOut) = pdpVerifier.getFILUSDPrice();
        assertEq(priceOut, uint64(6), "Price should be 6");
        assertEq(expoOut, int32(0), "Expo should be 0");
    }

    function testCompleteProvingPeriodE2E() public {
        // Mock Pyth oracle call to return $5 USD/FIL
        (bytes memory pythCallData, PythStructs.Price memory price) = createPythCallData();
        vm.mockCall(address(pdpVerifier.PYTH()), pythCallData, abi.encode(price));

        // Step 1: Create a data set
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);

        // Step 2: Add data `A` in scope for the first proving period
        // Note that the data in the first addPieces call is added to the first proving period
        uint256[] memory leafCountsA = new uint256[](2);
        leafCountsA[0] = 2;
        leafCountsA[1] = 3;
        bytes32[][][] memory treesA = new bytes32[][][](2);
        for (uint256 i = 0; i < leafCountsA.length; i++) {
            treesA[i] = ProofUtil.makeTree(leafCountsA[i]);
        }

        IPDPTypes.PieceData[] memory piecesPP1 = new IPDPTypes.PieceData[](2);
        piecesPP1[0] = makePiece(treesA[0], leafCountsA[0]);
        piecesPP1[1] = makePiece(treesA[1], leafCountsA[1]);
        pdpVerifier.addPieces(setId, piecesPP1, empty);
        // flush the original addPieces call
        pdpVerifier.nextProvingPeriod(setId, block.number + challengeFinalityDelay, empty);

        uint256 challengeRangePP1 = pdpVerifier.getChallengeRange(setId);
        assertEq(challengeRangePP1, pdpVerifier.getDataSetLeafCount(setId), "Last challenged leaf should be total leaf count - 1");

        // Step 3: Now that first challenge is set for sampling add more data `B` only in scope for the second proving period
        uint256[] memory leafCountsB = new uint256[](2);
        leafCountsB[0] = 4;
        leafCountsB[1] = 5;
        bytes32[][][] memory treesB = new bytes32[][][](2);
        for (uint256 i = 0; i < leafCountsB.length; i++) {
            treesB[i] = ProofUtil.makeTree(leafCountsB[i]);
        }

        IPDPTypes.PieceData[] memory piecesPP2 = new IPDPTypes.PieceData[](2);
        piecesPP2[0] = makePiece(treesB[0], leafCountsB[0]);
        piecesPP2[1] = makePiece(treesB[1], leafCountsB[1]);
        pdpVerifier.addPieces(setId, piecesPP2, empty);

        assertEq(pdpVerifier.getPieceLeafCount(setId, 0), leafCountsA[0], "sanity check: First piece leaf count should be correct");
        assertEq(pdpVerifier.getPieceLeafCount(setId, 1), leafCountsA[1], "Second piece leaf count should be correct");
        assertEq(pdpVerifier.getPieceLeafCount(setId, 2), leafCountsB[0], "Third piece leaf count should be correct");
        assertEq(pdpVerifier.getPieceLeafCount(setId, 3), leafCountsB[1], "Fourth piece leaf count should be correct");

        // CHECK: last challenged leaf doesn't move
        assertEq(pdpVerifier.getChallengeRange(setId), challengeRangePP1, "Last challenged leaf should not move");
        assertEq(pdpVerifier.getDataSetLeafCount(setId), leafCountsA[0] + leafCountsA[1] + leafCountsB[0] + leafCountsB[1], "Leaf count should only include non-removed pieces");

        // Step 5: schedule removal of first + second proving period data
        uint256[] memory piecesToRemove = new uint256[](2);
        piecesToRemove[0] = 1; // Remove the second piece from first proving period
        piecesToRemove[1] = 3; // Remove the second piece from second proving period
        pdpVerifier.schedulePieceDeletions(setId, piecesToRemove, empty);
        assertEq(pdpVerifier.getScheduledRemovals(setId), piecesToRemove, "Scheduled removals should match piecesToRemove");

        // Step 7: complete proving period 1.
        // Advance chain until challenge epoch.
        vm.roll(pdpVerifier.getNextChallengeEpoch(setId));
        // Prepare proofs.
        // Proving trees for PP1 are just treesA
        IPDPTypes.Proof[] memory proofsPP1 = buildProofs(pdpVerifier, setId, 5, treesA, leafCountsA);

        vm.mockCall(pdpVerifier.RANDOMNESS_PRECOMPILE(), abi.encode(pdpVerifier.getNextChallengeEpoch(setId)), abi.encode(pdpVerifier.getNextChallengeEpoch(setId)));

        pdpVerifier.provePossession{value: 1e18}(setId, proofsPP1);

        pdpVerifier.nextProvingPeriod(setId, block.number + challengeFinalityDelay, empty);
        // CHECK: leaf counts
        assertEq(pdpVerifier.getPieceLeafCount(setId, 0), leafCountsA[0], "First piece leaf count should be the set leaf count");
        assertEq(pdpVerifier.getPieceLeafCount(setId, 1), 0, "Second piece leaf count should be zeroed after removal");
        assertEq(pdpVerifier.getPieceLeafCount(setId, 2), leafCountsB[0], "Third piece leaf count should be the set leaf count");
        assertEq(pdpVerifier.getPieceLeafCount(setId, 3), 0, "Fourth piece leaf count should be zeroed after removal");
        assertEq(pdpVerifier.getDataSetLeafCount(setId), leafCountsA[0] + leafCountsB[0], "Leaf count should == size of non-removed pieces");
        assertEq(pdpVerifier.getChallengeRange(setId), leafCountsA[0] + leafCountsB[0], "Last challenged leaf should be total leaf count");

        // CHECK: scheduled removals are processed
        assertEq(pdpVerifier.getScheduledRemovals(setId), new uint256[](0), "Scheduled removals should be processed");

        // CHECK: the next challenge epoch has been updated
        assertEq(pdpVerifier.getNextChallengeEpoch(setId), block.number + challengeFinalityDelay, "Next challenge epoch should be updated");
    }
}

contract PDPVerifierMigrateTest is Test {
    PDPVerifier implementation;
    PDPVerifier newImplementation;
    MyERC1967Proxy proxy;

    function setUp() public {
        bytes memory initializeData = abi.encodeWithSelector(PDPVerifier.initialize.selector,2);
        implementation = new PDPVerifier();
        newImplementation = new PDPVerifier();
        proxy = new MyERC1967Proxy(address(implementation), initializeData);
    }

    function testMigrate() public {
        vm.expectEmit(true, true, true, true);
        emit IPDPEvents.ContractUpgraded(newImplementation.VERSION(), address(newImplementation));
        bytes memory migrationCall = abi.encodeWithSelector(PDPVerifier.migrate.selector);
        UUPSUpgradeable(address(proxy)).upgradeToAndCall(address(newImplementation), migrationCall);
        // Second call should fail because reinitializer(2) can only be called once
        vm.expectRevert("InvalidInitialization()");
        UUPSUpgradeable(address(proxy)).upgradeToAndCall(address(newImplementation), migrationCall);
    }
}
contract MockStorageProviderChangedListener is PDPListener {
    uint256 public lastDataSetId;
    address public lastOldStorageProvider;
    address public lastNewStorageProvider;
    bytes public lastExtraData;
    bool public shouldRevert;

    function setShouldRevert(bool value) external { shouldRevert = value; }

    function storageProviderChanged(uint256 dataSetId, address oldStorageProvider, address newStorageProvider, bytes calldata extraData) external override {
        if (shouldRevert) revert("MockStorageProviderChangedListener: forced revert");
        lastDataSetId = dataSetId;
        lastOldStorageProvider = oldStorageProvider;
        lastNewStorageProvider = newStorageProvider;
        lastExtraData = extraData;
    }
    function dataSetCreated(uint256, address, bytes calldata) external override {}
    function dataSetDeleted(uint256, uint256, bytes calldata) external override {}
    function piecesAdded(uint256, uint256, IPDPTypes.PieceData[] calldata, bytes calldata) external override {}
    function piecesScheduledRemove(uint256, uint256[] calldata, bytes calldata) external override {}
    function possessionProven(uint256, uint256, uint256, uint256) external override {}
    function nextProvingPeriod(uint256, uint256, uint256, bytes calldata) external override {}
}

contract PDPVerifierStorageProviderListenerTest is Test {
    PDPVerifier pdpVerifier;
    MockStorageProviderChangedListener listener;
    address public storageProvider;
    address public nextStorageProvider;
    address public nonStorageProvider;
    bytes empty = new bytes(0);

    function setUp() public {
        PDPVerifier pdpVerifierImpl = new PDPVerifier();
        bytes memory initializeData = abi.encodeWithSelector(
            PDPVerifier.initialize.selector,
            2
        );
        MyERC1967Proxy proxy = new MyERC1967Proxy(address(pdpVerifierImpl), initializeData);
        pdpVerifier = PDPVerifier(address(proxy));
        listener = new MockStorageProviderChangedListener();
        storageProvider = address(this);
        nextStorageProvider = address(0x1234);
        nonStorageProvider = address(0xffff);
    }

    function testStorageProviderChangedCalledOnStorageProviderTransfer() public {
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);
        pdpVerifier.proposeDataSetStorageProvider(setId, nextStorageProvider);
        vm.prank(nextStorageProvider);
        pdpVerifier.claimDataSetStorageProvider(setId, empty);
        assertEq(listener.lastDataSetId(), setId, "Data set ID mismatch");
        assertEq(listener.lastOldStorageProvider(), storageProvider, "Old storage provider mismatch");
        assertEq(listener.lastNewStorageProvider(), nextStorageProvider, "New storage provider mismatch");
    }

    function testNoListenerNoRevert() public {
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(0), empty);
        pdpVerifier.proposeDataSetStorageProvider(setId, nextStorageProvider);
        vm.prank(nextStorageProvider);
        pdpVerifier.claimDataSetStorageProvider(setId, empty);
      // No assertion needed, test passes if no revert
    }

    function testListenerRevertDoesNotRevertMainTx() public {
        uint256 setId = pdpVerifier.createDataSet{value: PDPFees.sybilFee()}(address(listener), empty);
        pdpVerifier.proposeDataSetStorageProvider(setId, nextStorageProvider);
        listener.setShouldRevert(true);
        vm.prank(nextStorageProvider);
        vm.expectRevert("MockStorageProviderChangedListener: forced revert");
        pdpVerifier.claimDataSetStorageProvider(setId, empty);
    }
}
