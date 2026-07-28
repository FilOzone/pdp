// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PDPVerifier} from "../src/PDPVerifier.sol";
import {COMPACT_PIECES_SLOT} from "../src/PDPVerifierLayout.sol";

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
