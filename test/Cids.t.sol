// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {Cids} from "../src/Cids.sol";

contract CidsTest is Test {
    function testDigestRoundTrip() public pure {
        bytes32 digest = 0xbeadcafefacedeedfeedbabedeadbeefbeadcafefacedeedfeedbabedeadbeef;
        Cids.Cid memory c = Cids.CommPv2FromDigest(0, 10, digest);
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
        assertEq(Cids.pieceSize(0, 30), 1 << (30 + 5));
        assertEq(Cids.pieceSize(127, 30), (1 << (30 + 5)) - 128);
        assertEq(Cids.pieceSize(128, 30), (1 << (30 + 5)) - 129);
    }

    function testLeafCount() public pure {
        assertEq(Cids.leafCount(0, 30), 1 << 30);
        assertEq(Cids.leafCount(127, 30), (1 << 30) - 4);
        assertEq(Cids.leafCount(128, 30), (1 << 30) - 4);
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
    function testReadUvarintIncomplete() public {
        // Test reading an incomplete uvarint that should revert
        bytes memory incompleteUvarint = hex"80"; // A single byte indicating more to come, but nothing follows
        vm.expectRevert(); // Expect any revert, specifically index out of bounds
        Cids._readUvarint(incompleteUvarint, 0);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testReadUvarintMSBSetOnLastByte() public {
        bytes memory incompleteUvarint2 = hex"ff81"; // MSB set on last byte.
        vm.expectRevert();
        Cids._readUvarint(incompleteUvarint2, 0);
    }

    function testReadUvarintWithOffset() public pure {
        // Test reading with an offset
        bytes memory bufferWithOffset = hex"00010203040506078001"; // Value 128 (8001) at offset 8
        (uint256 readValue, uint256 newOffset) = Cids._readUvarint(bufferWithOffset, 8);
        assertEq(readValue, 128, "Read uvarint with offset failed");
        assertEq(newOffset, 10, "Offset after reading with offset incorrect");
    }

    function testValidateCommPv2FRC0069() public pure {
        // The values are taken from FRC-0069 specification
        // Test vector 1: height=4, padding=0
        bytes memory cidData1 = hex"01559120220004496dae0cc9e265efe5a006e80626a5dc5c409e5d3155c13984caf6c8d5cfd605";
        Cids.Cid memory cid1 = Cids.Cid(cidData1);
        (uint256 padding1, uint8 height1, uint256 digestOffset1) = Cids.validateCommPv2(cid1);
        assertEq(padding1, 0, "CID 1 padding");
        assertEq(height1, 4, "CID 1 height");

        // Test vector 2: height=2, padding=0
        bytes memory cidData2 = hex"015591202200023731bb99ac689f66eef5973e4a94da188f4ddcae580724fc6f3fd60dfd488333";
        Cids.Cid memory cid2 = Cids.Cid(cidData2);
        (uint256 padding2, uint8 height2, uint256 digestOffset2) = Cids.validateCommPv2(cid2);
        assertEq(padding2, 0, "CID 2 padding");
        assertEq(height2, 2, "CID 2 height");

        // Test vector 3: height=5, padding=504
        bytes memory cidData3 = hex"0155912023f80305de6815dcb348843215a94de532954b60be550a4bec6e74555665e9a5ec4e0f3c";
        Cids.Cid memory cid3 = Cids.Cid(cidData3);
        (uint256 padding3, uint8 height3, uint256 digestOffset3) = Cids.validateCommPv2(cid3);
        assertEq(padding3, 504, "CID 3 padding");
        assertEq(height3, 5, "CID 3 height");

        // Verify that digestOffset points to valid data by checking a few bytes from the digest
        // For CID 1
        assertEq(cid1.data[digestOffset1], bytes1(0x49), "CID 1 digest first byte");
        // For CID 2
        assertEq(cid2.data[digestOffset2], bytes1(0x37), "CID 2 digest first byte");
        // For CID 3
        assertEq(cid3.data[digestOffset3], bytes1(0xde), "CID 3 digest first byte");
    }
}
