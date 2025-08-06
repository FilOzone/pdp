pragma solidity ^0.8.13;

import {Test, console, Vm} from "forge-std/Test.sol";
import {Cids} from "../src/Cids.sol";
import {IPDPTypes} from "../src/interfaces/IPDPTypes.sol";
import {BitOps} from "../src/BitOps.sol";

contract PieceHelper is Test {
    // Constructs a PieceData structure for a Merkle tree.
    function makePiece(bytes32[][] memory tree, uint leafCount) internal pure returns (IPDPTypes.PieceData memory) {
        if (leafCount == 0) {
            return IPDPTypes.PieceData(Cids.commpV2FromDigest(127, 2, tree[0][0]));
        }
        uint8 height = uint8(256 - BitOps.clz(leafCount - 1));
        require(1<<height >= leafCount, "makePiece: height not enough to hold leaf count");
        uint256 paddingLeaves = (1<<height) - leafCount;
        uint256 padding = (paddingLeaves * 32 * 127 + 127)/ 128;

        console.log("leafCount", leafCount);
        console.log("height", height);
        console.log("paddingLeaves", paddingLeaves);
        console.log("padding", padding);
        assertEq(Cids.leafCount(padding, height), leafCount, "makePiece: leaf count mismatch");
        return IPDPTypes.PieceData(Cids.commpV2FromDigest(padding,  height, tree[0][0]));
    }

    function makeSamplePiece(uint leafCount) internal pure returns (IPDPTypes.PieceData memory) {
        bytes32[][] memory tree = new bytes32[][](1);
        tree[0] = new bytes32[](1);
        tree[0][0] = bytes32(abi.encodePacked(leafCount));
        return makePiece(tree, leafCount);
    }

    // count here is bytes after Fr32 padding
    function makeSamplePieceBytes(uint count) internal pure returns (IPDPTypes.PieceData memory) {
        bytes32 digest = bytes32(abi.encodePacked(count));
        if (count == 0) {
            return IPDPTypes.PieceData(Cids.commpV2FromDigest(127, 2,  digest));
        }


        uint256 leafCount = (count+31) / 32;
        uint8 height = uint8(256 - BitOps.clz(leafCount - 1));
        require(1<<(height + 5) >= count, "makeSamplePieceBytes: height not enough to hold count");
        uint256 padding = (1 << (height + 5)) - count;
        padding = (padding * 127 + 127)/128;

        console.log("count", count);
        console.log("leafCount", leafCount);
        console.log("height", height);
        console.log("padding", padding);
        assertEq(Cids.leafCount(padding, height), leafCount, "makeSamplePieceBytes: leaf count mismatch");
        assertEq(Cids.pieceSize(padding, height), count, "makeSamplePieceBytes: piece size mismatch");

        return IPDPTypes.PieceData(Cids.commpV2FromDigest(padding,  height, digest));
    }
}

contract PieceHelperTest is Test, PieceHelper {
    function testMakePiece() pure public {
        bytes32[][] memory tree = new bytes32[][](1);
        tree[0] = new bytes32[](10);
        IPDPTypes.PieceData memory piece = makePiece(tree, 10);
        Cids.validateCommPv2(piece.piece);
    }

    function testMakeSamplePiece() pure public {
        makeSamplePiece(0);
        IPDPTypes.PieceData memory piece = makeSamplePiece(1);
        Cids.validateCommPv2(piece.piece);
        piece = makeSamplePiece(2);
        Cids.validateCommPv2(piece.piece);
        piece = makeSamplePiece(3);
        Cids.validateCommPv2(piece.piece);
        piece = makeSamplePiece(4);
        Cids.validateCommPv2(piece.piece);
        piece = makeSamplePiece(10);
        Cids.validateCommPv2(piece.piece);
        piece = makeSamplePiece(127);
        Cids.validateCommPv2(piece.piece);
        piece = makeSamplePiece(128);
        Cids.validateCommPv2(piece.piece);
        piece = makeSamplePiece(1024);
        Cids.validateCommPv2(piece.piece);
    }

    function testMakeSamplePieceBytes() pure public {
        IPDPTypes.PieceData memory piece = makeSamplePieceBytes(0);
        piece = makeSamplePieceBytes(1);
        Cids.validateCommPv2(piece.piece);
        piece = makeSamplePieceBytes(2);
        Cids.validateCommPv2(piece.piece);
        piece = makeSamplePieceBytes(32);
        Cids.validateCommPv2(piece.piece);
        piece = makeSamplePieceBytes(31);
        Cids.validateCommPv2(piece.piece);
        piece = makeSamplePieceBytes(127);
        Cids.validateCommPv2(piece.piece);
        piece = makeSamplePieceBytes(128);
        Cids.validateCommPv2(piece.piece);
    }
}
