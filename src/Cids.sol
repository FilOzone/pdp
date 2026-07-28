// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.20;

library Cids {
    //  0x01    0x55                0x9120
    // (cidv1)  (raw)  (fr32-sha2-256-trunc254-padded-binary-tree)
    bytes4 public constant COMMP_V2_PREFIX = hex"01559120";

    // A helper struct for events + getter functions to display digests as PieceCIDv2 CIDs
    struct Cid {
        bytes data;
    }

    // Checks that CID is PieceCIDv2 and decomposes it into its components.
    // See: https://github.com/filecoin-project/FIPs/blob/master/FRCs/frc-0069.md
    function validateCommPv2(Cid memory cid) internal pure returns (uint256 padding, uint8 height, bytes32 root) {
        require(cid.data.length >= 4, "Cid data is too short");
        for (uint256 i = 0; i < 4; i++) {
            if (cid.data[i] != COMMP_V2_PREFIX[i]) {
                revert("Cid must be CommPv2");
            }
        }

        uint256 offset = 4;
        uint256 mhLength;
        uint256 multihashOffset;
        (mhLength, multihashOffset) = _readUvarint(cid.data, offset);
        require(multihashOffset - offset == _uvarintLength(mhLength), "CommPv2 multihash length is not minimal");
        require(mhLength >= 34, "CommPv2 multihash length must be at least 34");
        if (mhLength != cid.data.length - multihashOffset) {
            revert("CommPv2 multihash length does not match data length");
        }

        offset = multihashOffset;
        uint256 paddingOffset;
        (padding, paddingOffset) = _readUvarint(cid.data, offset);
        require(paddingOffset - offset == _uvarintLength(padding), "CommPv2 padding is not minimal");

        offset = paddingOffset;
        require(offset < cid.data.length, "CommPv2 digest is too short");
        height = uint8(cid.data[offset++]);
        require(offset <= cid.data.length - 32, "CommPv2 digest is too short");
        require(offset == cid.data.length - 32, "CommPv2 digest length is invalid");

        bytes memory data = cid.data;
        assembly {
            root := mload(add(add(data, 0x20), offset))
        }
    }

    // isPaddingExcessive checks if the padding size exceeds the size of the tree
    // When this is false, leafCount will never return zero
    function isPaddingExcessive(uint256 padding, uint8 height) internal pure returns (bool) {
        return (128 * padding) / 127 >= 1 << (height + 5);
    }

    // pieceSize returns the size of the data defined by amount of padding and height of the tree
    // this is after the Fr32 expansion, if 1 bit of actual data spills into padding byte, the whole byte is counted as data
    // as the padding is specified as before expansion
    function pieceSize(uint256 padding, uint8 height) internal pure returns (uint256) {
        // 2^height * 32 - padding
        // we can fold the 32 into height
        return (1 << (uint256(height) + 5)) - (128 * padding) / 127;
    }

    // rawPieceSize returns the exact raw (pre-Fr32-expansion) byte size of the data behind a
    // PieceCIDv2. Per FRC-0069, the CID describes a binary tree of 2^height 32-byte leaves
    // holding Fr32-expanded data (128 Fr32 bytes per 127 raw), and `padding` is the trailing
    // zero bytes appended to the raw data before that expansion.
    //   raw size = 2^height * 32 * 127/128 - padding = 2^(height-2) * 127 - padding
    // Reverts on height < 2 or padding too large for the tree.
    function rawPieceSize(uint256 padding, uint8 height) internal pure returns (uint256) {
        return (1 << (uint256(height) - 2)) * 127 - padding;
    }

    // leafCount returns the number of 32b leaves that contain any amount of data
    // Utilize isPaddingExcessive to check if the padding size exceeds the size of the tree
    // If isPaddingExcessive is false, leafCount will never return a zero.
    function leafCount(uint256 padding, uint8 height) internal pure returns (uint256) {
        // the padding itself is # of bytes before Fr32 expansion
        // so we need to expand it by factor 128/127
        // then we divide by 32 with a floor to get the number of leaves that are fully padding
        uint256 paddingLeafs = (128 * padding) / 127 >> 5;
        // 1<<height is the number of leaves in the tree
        // which then after subtracting the padding leaves is the number of leaves that contain data
        return (1 << uint256(height)) - paddingLeafs;
    }

    // leafCountToRawSize approximates raw bytes from a data-bearing leaf count (sum of
    // Cids.leafCount across pieces, fully padded leaves excluded). Use rawPieceSize per piece
    // for an exact result. Overestimates by up to 31 bytes per piece.
    function leafCountToRawSize(uint256 leaves) internal pure returns (uint256) {
        return (leaves * 32 * 127) / 128;
    }

    // Creates a PieceCIDv2 CID from a raw size and hash digest according to FRC-0069.
    // The CID uses the Raw codec and fr32-sha2-256-trunc254-padded-binary-tree multihash.
    // The digest format is: uvarint padding | uint8 height | 32 byte root data
    function CommPv2FromDigest(uint256 padding, uint8 height, bytes32 digest) internal pure returns (Cids.Cid memory) {
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

    // Helper function reading uvarints <= 256 bits.
    // Returns (value, offset) with offset advanced to the following byte.
    function _readUvarint(bytes memory data, uint256 offset) internal pure returns (uint256 value, uint256 newOffset) {
        uint256 i;
        while (true) {
            require(offset + i < data.length, "Uvarint is unterminated");
            uint8 byteValue = uint8(data[offset + i]);
            uint8 payload = byteValue & 0x7F;
            if (i == 36) {
                require(payload <= 0x0F && byteValue < 0x80, "Uvarint overflows uint256");
            }
            value |= uint256(payload) << (i * 7);
            i++;
            if (byteValue < 0x80) {
                newOffset = offset + i;
                return (value, newOffset);
            }
        }
    }
}
