// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BitOps} from "./BitOps.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

library Cids {
    uint256 public constant COMMP_LEAF_SIZE = 32;
    //  0x01    0x55                0x9120                              0x21
    // (cidv1)  (raw)  (fr32-sha2-256-trunc254-padded-binary-tree)  (length of multihash)
    bytes4 public constant COMMP_V2_PREFIX = hex"01559120";

    // A helper struct for events + getter functions to display digests as CommpV2 CIDs
    struct Cid {
        bytes data;
    }

    // Returns the last 32 bytes of a CID payload as a bytes32.
    function digestFromCid(Cid memory cid) internal pure returns (bytes32) {
        require(cid.data.length >= 32, "Cid data is too short");
        bytes memory dataSlice = new bytes(32);
        for (uint256 i = 0; i < 32; i++) {
            dataSlice[i] = cid.data[cid.data.length - 32 + i];
        }
        return bytes32(dataSlice);
    }

    // Checks that cid matches Commpv2.
    function validateCommPv2(Cid memory cid)
        internal
        pure
        returns (uint256 padding, uint8 height, uint256 digestOffset)
    {
        for (uint256 i = 0; i < 4; i++) {
            if (cid.data[i] != COMMP_V2_PREFIX[i]) {
                revert("Cid must be CommPv2");
            }
        }
        uint256 offset = 4;
        uint256 mhLength;
        (mhLength, offset) = _readUvarint(cid.data, offset);
        require(mhLength >= 34, "CommPv2 multihash length must be at least 34");
        if (mhLength + offset != cid.data.length) {
            // output lengths in revert
            //revert("CommPv2 multihash length does not match data length", mhLength, cid.data.length);
            // revert doesn't take multiple arguments
            revert(string.concat("CommPv2 multihash length does not match data length", Strings.toString(mhLength), " ", Strings.toString(offset), " ",Strings.toString(cid.data.length)));
        }
        (padding, offset) = _readUvarint(cid.data, offset);

        height = uint8(cid.data[offset]);
        if ((128*padding)/127 >= 1<<(height+5)) {
            revert("Too much CommPv2 padding");
        }
        offset++;

        return (padding, height, offset);
    }

    // pieceSize resturns the size of the data defined by amount of padding and height of the tree
    // this is after the Fr32 expansion, if 1 bit of actual data spills into padding byte, the whole byte is counted as data
    // as the padding is specified as before expansion
    function pieceSize(uint256 padding, uint8 height) internal pure returns (uint256) {
        // 2^height * 32 - padding
        // we can fold the 32 into height
        return (1 << (uint256(height)+5)) - (128*padding)/127;
    }

    function leafCount(uint256 padding, uint8 height) internal pure returns (uint256) {
        // the number of leaves that are fully padding
        uint256 paddingLeafs = (128*padding)/127 >> 5;
        return (1 << uint256(height)) - paddingLeafs;
    }



    // Creates a CommPv2 CID from a raw size and hash digest according to FRC-0069.
    // The CID uses the Raw codec (0x55) and fr32-sha2-256-trunc254-padded-binary-tree multihash (0x1011).
    // The digest format is: uvarint padding | uint8 height | 32 byte root data
    function commpV2FromDigest(uint256 padding, uint8 height, bytes32 digest) internal pure returns (Cids.Cid memory) {
        // Create the CID
        // Format: CIDv1 (0x01) | Raw codec (0x55) | fr32-sha2-256-trunc254-padded-binary-tree multihash (0x1011) | uvarint multihash length | multihash digest
        // multihash digest:
        // Format: uvarint padding | uint8 height | 32 byte root data
        uint256 multihashLength = _uvarintLength(padding) + 1 + 32;
        bytes memory cidData = new bytes(4 + _uvarintLength(multihashLength) + multihashLength);
        cidData[0] = COMMP_V2_PREFIX[0]; // CIDv1
        cidData[1] = COMMP_V2_PREFIX[1]; // Raw codec
        cidData[2] = COMMP_V2_PREFIX[2]; // fr32-sha2-256-trunc254-padded-binary-tree multihash (high byte)
        cidData[3] = COMMP_V2_PREFIX[3]; // fr32-sha2-256-trunc254-padded-binary-tree multihash (low byte)
        uint256 offset = 4;

        // Write multihash length as uvarint
        offset = _writeUvarint(cidData, offset, multihashLength);

        // Write padding as uvarint
        offset = _writeUvarint(cidData, offset, padding);

        // Write height
        cidData[offset++] = bytes1(height);

        // Write root data
        for (uint256 i = 0; i < 32; i++) {
            cidData[offset + i] = bytes1(digest << (i * 8));
        }

        return Cids.Cid(cidData);
    }

    // Helper function to write a uvarint to a bytes array
    function _writeUvarint(bytes memory data, uint256 offset, uint256 value) internal pure returns (uint256) {
        while (value >= 0x80) {
            data[offset++] = bytes1(uint8(value) | 0x80);
            value >>= 7;
        }
        data[offset++] = bytes1(uint8(value));
        return offset;
    }

    // Helper function to calculate the length of a uvarint
    function _uvarintLength(uint256 value) internal pure returns (uint256) {
        uint256 length = 1;
        while (value >= 0x80) {
            value >>= 7;
            length++;
        }
        return length;
    }

    // Helper function reading uvarints <= 256 bits
    // returns (value, offset) with offset advanced to the following byte
    function _readUvarint(bytes memory data, uint256 offset) internal pure returns (uint256, uint256) {
        uint256 i = 0;
        uint256 value = uint256(uint8(data[offset])) & 0x7F;
        while (data[offset+i] >= 0x80) {
            i++;
            value = value | uint256(uint8(data[offset+i]) & 0x7F) << (i * 7);
        }
        i++;
        return (value, offset+i);
    }
}
