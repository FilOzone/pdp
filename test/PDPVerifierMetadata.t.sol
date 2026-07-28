// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PDPVerifier} from "../src/PDPVerifier.sol";
import {Cids} from "../src/Cids.sol";
import {COMPACT_PIECES_SLOT} from "../src/PDPVerifierLayout.sol";
import {IPDPTypes} from "../src/interfaces/IPDPTypes.sol";

contract PDPVerifierMetadataHarness is PDPVerifier {
    constructor() PDPVerifier(1, 2) {}

    function packPieceMetadata(uint256 padding, uint256 height, uint256 leafCount, uint256 sum)
        external
        pure
        returns (uint256)
    {
        return _packPieceMetadata(padding, height, leafCount, sum);
    }

    function piecePadding(uint256 metadata) external pure returns (uint256) {
        return _piecePadding(metadata);
    }

    function pieceHeight(uint256 metadata) external pure returns (uint256) {
        return _pieceHeight(metadata);
    }

    function pieceLeafCount(uint256 metadata) external pure returns (uint256) {
        return _pieceLeafCount(metadata);
    }

    function pieceSum(uint256 metadata) external pure returns (uint256) {
        return _pieceSum(metadata);
    }

    function withPieceSum(uint256 metadata, uint256 sum) external pure returns (uint256) {
        return _withPieceSum(metadata, sum);
    }

    function clearPieceMetadataExceptSum(uint256 metadata) external pure returns (uint256) {
        return _clearPieceMetadataExceptSum(metadata);
    }

    function appendCompactPiece(uint256 setId, bytes32 root, uint256 metadata) external {
        compactPieces[setId].push(PieceV2(root, metadata));
    }

    function addPiecesForTest(uint256 setId, Cids.Cid[] calldata pieces) external returns (uint256) {
        return _addPiecesToDataSet(setId, pieces, bytes(""));
    }

    function compactPiece(uint256 setId, uint256 pieceId) external view returns (bytes32 root, uint256 metadata) {
        PieceV2 storage piece = compactPieces[setId][pieceId];
        return (piece.root, piece.metadata);
    }

    function compactPieceCount(uint256 setId) external view returns (uint256) {
        return compactPieces[setId].length;
    }

    function setDataSetLeafCount(uint256 setId, uint256 leafCount) external {
        dataSetLeafCount[setId] = leafCount;
    }

    function dataSetLeafCountForTest(uint256 setId) external view returns (uint256) {
        return dataSetLeafCount[setId];
    }

    function removePiecesForTest(uint256 setId, uint256[] calldata pieceIds) external {
        storageProvider[setId] = msg.sender;
        removePieces(setId, pieceIds);
    }
}

contract PDPVerifierMetadataTest is Test {
    uint256 private constant PADDING_MAX = (uint256(1) << 55) - 1;
    uint256 private constant HEIGHT_MAX = (uint256(1) << 6) - 1;
    uint256 private constant LEAF_COUNT_MAX = (uint256(1) << 51) - 1;
    uint256 private constant SUM_TREE_MAX = (uint256(1) << 144) - 1;

    PDPVerifierMetadataHarness private harness;

    function setUp() public {
        harness = new PDPVerifierMetadataHarness();
    }

    function testPackPieceMetadataZeroRoundTrip() public view {
        uint256 metadata = harness.packPieceMetadata(0, 0, 0, 0);
        assertEq(metadata, 0, "zero metadata");
        _assertMetadata(metadata, 0, 0, 0, 0);
    }

    function testPackPieceMetadataFieldBoundaryBits() public view {
        _assertRoundTrip(1, 0, 0, 0);
        _assertRoundTrip(uint256(1) << 54, 0, 0, 0);
        _assertRoundTrip(0, 1, 0, 0);
        _assertRoundTrip(0, uint256(1) << 5, 0, 0);
        _assertRoundTrip(0, 0, 1, 0);
        _assertRoundTrip(0, 0, uint256(1) << 50, 0);
        _assertRoundTrip(0, 0, 0, 1);
        _assertRoundTrip(0, 0, 0, uint256(1) << 143);
    }

    function testPackPieceMetadataFieldMaxima() public view {
        _assertRoundTrip(PADDING_MAX, 0, 0, 0);
        _assertRoundTrip(0, HEIGHT_MAX, 0, 0);
        _assertRoundTrip(0, 0, LEAF_COUNT_MAX, 0);
        _assertRoundTrip(0, 0, 0, SUM_TREE_MAX);
    }

    function testPackPieceMetadataCombinedMaximaDoNotOverlap() public view {
        uint256 metadata = harness.packPieceMetadata(PADDING_MAX, HEIGHT_MAX, LEAF_COUNT_MAX, SUM_TREE_MAX);
        assertEq(metadata, type(uint256).max, "all metadata bits set");
        _assertMetadata(metadata, PADDING_MAX, HEIGHT_MAX, LEAF_COUNT_MAX, SUM_TREE_MAX);
    }

    function testPackPieceMetadataRejectsOverflowingFields() public {
        vm.expectRevert(PDPVerifier.PieceMetadataOverflow.selector);
        harness.packPieceMetadata(PADDING_MAX + 1, 0, 0, 0);

        vm.expectRevert(PDPVerifier.PieceMetadataOverflow.selector);
        harness.packPieceMetadata(0, HEIGHT_MAX + 1, 0, 0);

        vm.expectRevert(PDPVerifier.PieceMetadataOverflow.selector);
        harness.packPieceMetadata(0, 0, LEAF_COUNT_MAX + 1, 0);

        vm.expectRevert(PDPVerifier.PieceMetadataOverflow.selector);
        harness.packPieceMetadata(0, 0, 0, SUM_TREE_MAX + 1);

        vm.expectRevert(PDPVerifier.PieceMetadataOverflow.selector);
        harness.withPieceSum(0, SUM_TREE_MAX + 1);
    }

    function testWithPieceSumPreservesPieceFields() public view {
        uint256 metadata = harness.packPieceMetadata(7, 12, 17, 23);
        uint256 replaced = harness.withPieceSum(metadata, SUM_TREE_MAX);
        _assertMetadata(replaced, 7, 12, 17, SUM_TREE_MAX);
    }

    function testClearPieceMetadataExceptSumPreservesSum() public view {
        uint256 metadata = harness.packPieceMetadata(PADDING_MAX, HEIGHT_MAX, LEAF_COUNT_MAX, SUM_TREE_MAX);
        uint256 cleared = harness.clearPieceMetadataExceptSum(metadata);
        _assertMetadata(cleared, 0, 0, 0, SUM_TREE_MAX);
    }

    function testCompactPiecesLayoutUsesTwoContiguousSlots() public {
        uint256 setId = 9;
        bytes32 root = keccak256("root");
        uint256 metadata = harness.packPieceMetadata(3, 4, 5, 6);
        harness.appendCompactPiece(setId, root, metadata);

        bytes32 arrayHeader = keccak256(abi.encode(setId, uint256(COMPACT_PIECES_SLOT)));
        uint256 elementBase = uint256(keccak256(abi.encode(arrayHeader)));
        assertEq(vm.load(address(harness), bytes32(elementBase)), root, "root occupies member slot zero");
        assertEq(
            vm.load(address(harness), bytes32(elementBase + 1)), bytes32(metadata), "metadata occupies member slot one"
        );
    }

    function testCompactAdditionAppendsRootsMetadataAndFenwickSums() public {
        uint256 setId = 9;
        Cids.Cid[] memory firstBatch = new Cids.Cid[](3);
        firstBatch[0] = Cids.CommPv2FromDigest(0, 0, bytes32(uint256(1)));
        firstBatch[1] = Cids.CommPv2FromDigest(0, 1, bytes32(uint256(2)));
        firstBatch[2] = Cids.CommPv2FromDigest(0, 2, bytes32(uint256(3)));

        assertEq(harness.addPiecesForTest(setId, firstBatch), 0, "first batch starts at zero");
        assertEq(harness.compactPieceCount(setId), 3, "first batch appends three pieces");

        Cids.Cid[] memory secondBatch = new Cids.Cid[](2);
        secondBatch[0] = Cids.CommPv2FromDigest(0, 3, bytes32(uint256(4)));
        secondBatch[1] = Cids.CommPv2FromDigest(0, 4, bytes32(uint256(5)));

        assertEq(harness.addPiecesForTest(setId, secondBatch), 3, "later batch starts at compact length");
        assertEq(harness.compactPieceCount(setId), 5, "array length grows monotonically");
        assertEq(harness.dataSetLeafCountForTest(setId), 31, "batch leaf counts accumulate once");

        uint256[5] memory expectedLeafCounts = [uint256(1), 2, 4, 8, 16];
        uint256[5] memory expectedSums = [uint256(1), 3, 4, 15, 16];
        for (uint256 pieceId; pieceId < 5; ++pieceId) {
            (bytes32 root, uint256 metadata) = harness.compactPiece(setId, pieceId);
            assertEq(root, bytes32(pieceId + 1), "root");
            assertEq(harness.piecePadding(metadata), 0, "padding");
            assertEq(harness.pieceHeight(metadata), pieceId, "height");
            assertEq(harness.pieceLeafCount(metadata), expectedLeafCounts[pieceId], "leaf count");
            assertEq(harness.pieceSum(metadata), expectedSums[pieceId], "Fenwick partial sum");
        }
    }

    function testCompactRemovalOfLeafNodePreservesAncestorSumAndLookup() public {
        uint256 setId = 9;
        Cids.Cid[] memory pieces = new Cids.Cid[](3);
        pieces[0] = Cids.CommPv2FromDigest(0, 0, bytes32(uint256(1)));
        pieces[1] = Cids.CommPv2FromDigest(0, 1, bytes32(uint256(2)));
        pieces[2] = Cids.CommPv2FromDigest(0, 2, bytes32(uint256(3)));
        harness.addPiecesForTest(setId, pieces);

        uint256[] memory removed = new uint256[](1);
        removed[0] = 0;
        harness.removePiecesForTest(setId, removed);

        (bytes32 root, uint256 metadata) = harness.compactPiece(setId, 0);
        assertEq(root, bytes32(0), "removed root cleared");
        _assertMetadata(metadata, 0, 0, 0, 0);
        (, uint256 ancestorMetadata) = harness.compactPiece(setId, 1);
        _assertMetadata(ancestorMetadata, 0, 1, 2, 2);
        assertEq(harness.compactPieceCount(setId), 3, "ordinary removal keeps stable IDs");

        uint256[] memory leaves = new uint256[](2);
        leaves[0] = 0;
        leaves[1] = 2;
        IPDPTypes.PieceIdAndOffset[] memory found = harness.findPieceIds(setId, leaves);
        assertEq(found[0].pieceId, 1, "lookup crosses removed left boundary");
        assertEq(found[0].offset, 0, "first surviving piece offset");
        assertEq(found[1].pieceId, 2, "lookup reaches piece after boundary");
        assertEq(found[1].offset, 0, "second surviving piece offset");
    }

    function testCompactRemovalOfInternalNodeRetainsPartialSumAndAppendsAtTail() public {
        uint256 setId = 10;
        Cids.Cid[] memory pieces = new Cids.Cid[](3);
        pieces[0] = Cids.CommPv2FromDigest(0, 0, bytes32(uint256(1)));
        pieces[1] = Cids.CommPv2FromDigest(0, 1, bytes32(uint256(2)));
        pieces[2] = Cids.CommPv2FromDigest(0, 2, bytes32(uint256(3)));
        harness.addPiecesForTest(setId, pieces);

        uint256[] memory removed = new uint256[](1);
        removed[0] = 1;
        harness.removePiecesForTest(setId, removed);

        (bytes32 root, uint256 metadata) = harness.compactPiece(setId, 1);
        assertEq(root, bytes32(0), "removed root cleared");
        _assertMetadata(metadata, 0, 0, 0, 1);
        assertFalse(harness.pieceLive(setId, 1), "removed internal node is not live");
        assertEq(harness.getPieceLeafCount(setId, 1), 0, "removed internal node has zero leaves");

        uint256[] memory leaves = new uint256[](2);
        leaves[0] = 0;
        leaves[1] = 1;
        IPDPTypes.PieceIdAndOffset[] memory found = harness.findPieceIds(setId, leaves);
        assertEq(found[0].pieceId, 0, "lookup retains piece before removed boundary");
        assertEq(found[1].pieceId, 2, "lookup crosses removed internal boundary");

        Cids.Cid[] memory append = new Cids.Cid[](1);
        append[0] = Cids.CommPv2FromDigest(0, 0, bytes32(uint256(4)));
        assertEq(harness.addPiecesForTest(setId, append), 3, "append does not fill removed hole");
        assertEq(harness.compactPieceCount(setId), 4, "append grows compact array tail");
    }

    function testCompactAdditionRevertsEntireInvalidBatch() public {
        uint256 setId = 10;
        Cids.Cid[] memory pieces = new Cids.Cid[](2);
        pieces[0] = Cids.CommPv2FromDigest(0, 0, bytes32(uint256(1)));
        pieces[1] = Cids.Cid(bytes(""));

        vm.expectRevert("Cid data is too short");
        harness.addPiecesForTest(setId, pieces);

        assertEq(harness.compactPieceCount(setId), 0, "invalid batch leaves no compact pieces");
        assertEq(harness.dataSetLeafCountForTest(setId), 0, "invalid batch leaves total unchanged");
    }

    function testCompactAdditionRejectsDataSetLeafCountOverflow() public {
        uint256 setId = 11;
        harness.setDataSetLeafCount(setId, SUM_TREE_MAX);
        Cids.Cid[] memory pieces = new Cids.Cid[](1);
        pieces[0] = Cids.CommPv2FromDigest(0, 0, bytes32(uint256(1)));

        vm.expectRevert(PDPVerifier.PieceMetadataOverflow.selector);
        harness.addPiecesForTest(setId, pieces);

        assertEq(harness.compactPieceCount(setId), 0, "overflow leaves no compact pieces");
        assertEq(harness.dataSetLeafCountForTest(setId), SUM_TREE_MAX, "overflow leaves total unchanged");
    }

    function testCompactAdditionRejectsFenwickSumOverflow() public {
        uint256 setId = 12;
        harness.appendCompactPiece(setId, bytes32(uint256(1)), harness.packPieceMetadata(0, 0, 1, SUM_TREE_MAX));
        Cids.Cid[] memory pieces = new Cids.Cid[](1);
        pieces[0] = Cids.CommPv2FromDigest(0, 0, bytes32(uint256(2)));

        vm.expectRevert(PDPVerifier.PieceMetadataOverflow.selector);
        harness.addPiecesForTest(setId, pieces);

        assertEq(harness.compactPieceCount(setId), 1, "sum overflow adds no compact piece");
    }

    function _assertRoundTrip(uint256 padding, uint256 height, uint256 leafCount, uint256 sum) private view {
        _assertMetadata(harness.packPieceMetadata(padding, height, leafCount, sum), padding, height, leafCount, sum);
    }

    function _assertMetadata(uint256 metadata, uint256 padding, uint256 height, uint256 leafCount, uint256 sum)
        private
        view
    {
        assertEq(harness.piecePadding(metadata), padding, "padding");
        assertEq(harness.pieceHeight(metadata), height, "height");
        assertEq(harness.pieceLeafCount(metadata), leafCount, "leaf count");
        assertEq(harness.pieceSum(metadata), sum, "sum tree count");
    }
}
