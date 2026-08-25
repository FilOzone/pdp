// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Cids} from "../src/Cids.sol";
import {BitOps} from "../src/BitOps.sol";
import {PDPVerifier} from "../src/PDPVerifier.sol";
import {LEGACY_PIECE_STORAGE_ID_LIMIT_SLOT} from "../src/PDPVerifierLayout.sol";

contract PieceHelper is Test {
    function _configurePieceStorage(PDPVerifier verifier) internal {
        if (vm.envOr("PDP_TEST_LEGACY_STORAGE", false)) {
            vm.store(address(verifier), LEGACY_PIECE_STORAGE_ID_LIMIT_SLOT, bytes32(0));
            assertEq(verifier.legacyPieceStorageIdLimit(), 0, "legacy piece storage not enabled");
        }
    }

    function validateCommPv2(Cids.Cid calldata cid)
        external
        pure
        returns (uint256 padding, uint8 height, bytes32 root)
    {
        return Cids.validateCommPv2(cid);
    }

    function packCid(Cids.Cid memory cid) internal pure returns (Cids.PackedCid memory) {
        require(cid.data.length >= 32 && cid.data.length <= 64, "packCid: unsupported CID length");
        uint256 headerLength = cid.data.length - 32;
        uint256 header;
        uint256 root;
        for (uint256 i = 0; i < headerLength; i++) {
            header = (header << 8) | uint8(cid.data[i]);
        }
        for (uint256 i = headerLength; i < cid.data.length; i++) {
            root = (root << 8) | uint8(cid.data[i]);
        }
        return Cids.PackedCid({header: bytes32(header), root: bytes32(root)});
    }

    function packCids(Cids.Cid[] memory cids) internal pure returns (Cids.PackedCid[] memory) {
        return packCids(cids, 0, cids.length);
    }

    function packCids(Cids.Cid[] memory cids, uint256 start, uint256 length)
        internal
        pure
        returns (Cids.PackedCid[] memory packed)
    {
        require(start <= cids.length && length <= cids.length - start, "packCids: slice out of bounds");
        packed = new Cids.PackedCid[](length);
        for (uint256 i = 0; i < length; i++) {
            packed[i] = packCid(cids[start + i]);
        }
    }

    // Constructs a PieceData structure for a Merkle tree.
    function makePiece(bytes32[][] memory tree, uint256 leafCount) internal pure returns (Cids.Cid memory) {
        if (leafCount == 0) {
            return Cids.CommPv2FromDigest(127, 2, tree[0][0]);
        }
        uint8 height = uint8(256 - BitOps.clz(leafCount - 1));
        require(1 << height >= leafCount, "makePiece: height not enough to hold leaf count");
        uint256 paddingLeaves = (1 << height) - leafCount;
        uint256 padding = (paddingLeaves * 32 * 127 + 127) / 128;

        console.log("leafCount", leafCount);
        console.log("height", height);
        console.log("paddingLeaves", paddingLeaves);
        console.log("padding", padding);
        assertEq(Cids.leafCount(padding, height), leafCount, "makePiece: leaf count mismatch");
        return Cids.CommPv2FromDigest(padding, height, tree[0][0]);
    }

    function makePieceBytes(bytes32[][] memory tree, uint256 count) internal pure returns (Cids.Cid memory) {
        if (count == 0) {
            return Cids.CommPv2FromDigest(127, 2, tree[0][0]);
        }
        if (count == 1) {
            // piece with just 1 data byte doesn't exist
            // it is either 0 data bytes or two
            count = 2;
        }

        uint256 leafCount = (count + 31) / 32;
        uint8 height = uint8(256 - BitOps.clz(leafCount - 1));
        if (height < 2) {
            height = 2;
        }

        require(1 << (height + 5) >= count, "makeSamplePieceBytes: height not enough to hold count");
        uint256 padding = (1 << (height + 5)) - count;
        padding = (padding * 127 + 127) / 128;

        console.log("count", count);
        console.log("leafCount", leafCount);
        console.log("height", height);
        console.log("padding", padding);
        assertEq(Cids.leafCount(padding, height), leafCount, "makeSamplePieceBytes: leaf count mismatch");
        assertEq(Cids.pieceSize(padding, height), count, "makeSamplePieceBytes: piece size mismatch");
        return Cids.CommPv2FromDigest(padding, height, tree[0][0]);
    }

    function makeSamplePiece(uint256 leafCount) internal pure returns (Cids.Cid memory) {
        bytes32[][] memory tree = new bytes32[][](1);
        tree[0] = new bytes32[](1);
        tree[0][0] = bytes32(abi.encodePacked(leafCount));
        return makePiece(tree, leafCount);
    }

    // count here is bytes after Fr32 padding
    function makeSamplePieceBytes(uint256 count) internal pure returns (Cids.Cid memory) {
        bytes32[][] memory tree = new bytes32[][](1);
        tree[0] = new bytes32[](1);
        tree[0][0] = bytes32(abi.encodePacked(count));
        return makePieceBytes(tree, count);
    }
}

contract PieceHelperTest is Test, PieceHelper {
    function testMakePiece() public view {
        bytes32[][] memory tree = new bytes32[][](1);
        tree[0] = new bytes32[](10);
        Cids.Cid memory piece = makePiece(tree, 10);
        this.validateCommPv2(piece);
    }

    function testMakeSamplePiece() public view {
        makeSamplePiece(0);
        Cids.Cid memory piece = makeSamplePiece(1);
        this.validateCommPv2(piece);
        piece = makeSamplePiece(2);
        this.validateCommPv2(piece);
        piece = makeSamplePiece(3);
        this.validateCommPv2(piece);
        piece = makeSamplePiece(4);
        this.validateCommPv2(piece);
        piece = makeSamplePiece(10);
        this.validateCommPv2(piece);
        piece = makeSamplePiece(127);
        this.validateCommPv2(piece);
        piece = makeSamplePiece(128);
        this.validateCommPv2(piece);
        piece = makeSamplePiece(1024);
        this.validateCommPv2(piece);
    }

    function testMakeSamplePieceBytes() public view {
        Cids.Cid memory piece = makeSamplePieceBytes(0);
        piece = makeSamplePieceBytes(1);
        this.validateCommPv2(piece);
        piece = makeSamplePieceBytes(2);
        this.validateCommPv2(piece);
        piece = makeSamplePieceBytes(32);
        this.validateCommPv2(piece);
        piece = makeSamplePieceBytes(31);
        this.validateCommPv2(piece);
        piece = makeSamplePieceBytes(127);
        this.validateCommPv2(piece);
        piece = makeSamplePieceBytes(128);
        this.validateCommPv2(piece);
    }
}
