// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Cids} from "../src/Cids.sol";

contract CidsTest is Test {
    function testDigestRoundTrip() public pure {
        bytes32 digest = 0xbeadcafefacedeedfeedbabedeadbeefbeadcafefacedeedfeedbabedeadbeef;
        Cids.Cid memory c = Cids.commpV2FromDigest(0, 10, digest);
        assertEq(c.data.length, 39);
        bytes32 foundDigest = Cids.digestFromCid(c);
        assertEq(foundDigest, digest, "digest equal");

        (uint256 padding, uint8 height, uint256 digestOffset) = Cids.validateCommPv2(c);
        assertEq(padding, 0, "padding");
        assertEq(height, 10, "height");

        // assert that digest is same at digestOffset
        for (uint256 i = 0; i < 32; i++) {
            assertEq(bytes1(digest[i]), c.data[digestOffset + i], "bytes");
        }
    }

    function testPieceSize() public pure {
        assertEq(Cids.pieceSize(0, 30), 1<<(30+5));
        assertEq(Cids.pieceSize(127,  30), (1<<(30+5)) - 128);
        assertEq(Cids.pieceSize(128,  30), (1<<(30+5)) - 129);
    }
    function testLeafCount() public pure {
        assertEq(Cids.leafCount(0, 30), 1<<30);
        assertEq(Cids.leafCount(127,  30), (1<<30) - 4);
        assertEq(Cids.leafCount(128,  30), (1<<30) - 4);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testDigestTooShort() public {
        bytes memory byteArray = new bytes(31);
        for (uint256 i = 0; i < 31; i++) {
            byteArray[i] = bytes1(uint8(i));
        }
        Cids.Cid memory c = Cids.Cid(byteArray);
        vm.expectRevert("Cid data is too short");
        Cids.digestFromCid(c);
    }

    function testUvarintLength() public pure {
        assertEq(Cids._uvarintLength(0), 1);
        assertEq(Cids._uvarintLength(1), 1);
        assertEq(Cids._uvarintLength(127), 1);
        assertEq(Cids._uvarintLength(128), 2);
        assertEq(Cids._uvarintLength(16383), 2);
        assertEq(Cids._uvarintLength(16384), 3);
        assertEq(Cids._uvarintLength(2097151), 3);
        assertEq(Cids._uvarintLength(2097152), 4);
        assertEq(Cids._uvarintLength(type(uint256).max), 37);
    }

    function testUvarintRoundTrip() public pure {
        uint256[] memory values = new uint256[](7);
        values[0] = 0;
        values[1] = 1;
        values[2] = 127;
        values[3] = 128;
        values[4] = 16384;
        values[5] = 2097152;
        values[6] = type(uint256).max;

        uint256 totalLength = 0;
        for (uint256 i = 0; i < values.length; i++) {
            totalLength += Cids._uvarintLength(values[i]);
        }
        bytes memory buffer = new bytes(totalLength);
        uint256 offset = 0;

        // Write all values
        for (uint256 i = 0; i < values.length; i++) {
            offset = Cids._writeUvarint(buffer, offset, values[i]);
        }

        // Read all values and verify
        uint256 currentOffset = 0;
        for (uint256 i = 0; i < values.length; i++) {
            (uint256 readValue, uint256 newOffset) = Cids._readUvarint(buffer, currentOffset);
            assertEq(readValue, values[i], "Uvarint round trip failed");
            currentOffset = newOffset;
        }
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testReadUvarintEdgeCases() public {
        // Test reading an incomplete uvarint that should revert
        bytes memory incompleteUvarint = hex"80"; // A single byte indicating more to come, but nothing follows
        vm.expectRevert(); // Expect any revert, specifically index out of bounds
        Cids._readUvarint(incompleteUvarint, 0);

        bytes memory incompleteUvarint2 = hex"ff01"; // MSB set on last byte.
        vm.expectRevert();
        Cids._readUvarint(incompleteUvarint2, 0);

        // Test reading with an offset
        bytes memory bufferWithOffset = hex"00010203040506078001"; // Value 128 (8001) at offset 8
        (uint256 readValue, uint256 newOffset) = Cids._readUvarint(bufferWithOffset, 8);
        assertEq(readValue, 128, "Read uvarint with offset failed");
        assertEq(newOffset, 10, "Offset after reading with offset incorrect");
    }
}
