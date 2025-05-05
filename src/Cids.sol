// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

library Cids {
    // TODO PERF: https://github.com/FILCAT/pdp/issues/16#issuecomment-2329836995
    struct Cid {
        bytes data;
    }

    // Returns the last 32 bytes of a CID payload as a bytes32.
    function digestFromCid(Cid memory cid) internal pure returns (bytes32) {
        require(cid.data.length >= 32, "Cid data is too short");
        bytes memory dataSlice = new bytes(32);
        for (uint i = 0; i < 32; i++) {
            dataSlice[i] = cid.data[cid.data.length - 32 + i];
        }
        return bytes32(dataSlice);
    }

    // Makes a CID from a prefix and a digest.
    // The prefix doesn't matter to these contracts, which only inspect the last 32 bytes (the hash digest).
    function cidFromDigest(bytes memory prefix, bytes32 digest) internal pure returns (Cids.Cid memory) {
        bytes memory byteArray = new bytes(prefix.length + 32);
        for (uint256 i = 0; i < prefix.length; i++) {
            byteArray[i] = prefix[i];
        }
        for (uint256 i = 0; i < 32; i++) {
            byteArray[i+prefix.length] = bytes1(digest << (i * 8));
        }
        return Cids.Cid(byteArray);
    }

    // Creates a CommPv2 CID from a raw size and hash digest according to FRC-0069.
    // The CID uses the Raw codec (0x55) and fr32-sha2-256-trunc254-padded-binary-tree multihash (0x1011).
    // The digest format is: uvarint padding | uint8 height | 32 byte root data
    function commPv2FromDigest(uint256 rawSize, bytes32 digest) internal pure returns (Cids.Cid memory) {
        // Calculate padding and height
        uint256 padding;
        uint8 height;
        
        if (rawSize < 127) {
            // If data < 127 bytes, pad to 127 bytes
            padding = 127 - rawSize;
            height = 2; // 127 bytes = 2^7 * 127/128
        } else {
            // Calculate the next multiple of 127/128 bytes
            uint256 paddedSize = ((rawSize * 128 + 126) / 127) * 127;
            padding = paddedSize - rawSize;
            
            // Calculate height based on padded size
            // height = log2(paddedSize * 128/127)
            uint256 sizeInLeaves = paddedSize * 128 / 127;
            height = 0;
            while (sizeInLeaves > 1) {
                sizeInLeaves >>= 1;
                height++;
            }
        }

        // Create the multihash digest
        // Format: uvarint padding | uint8 height | 32 byte root data
        bytes memory multihashDigest = new bytes(33 + _uvarintLength(padding));
        uint256 offset = 0;
        
        // Write padding as uvarint
        offset = _writeUvarint(multihashDigest, offset, padding);
        
        // Write height
        multihashDigest[offset++] = bytes1(height);
        
        // Write root data
        for (uint256 i = 0; i < 32; i++) {
            multihashDigest[offset + i] = bytes1(digest << (i * 8));
        }
        
        // Create the CID
        // Format: CIDv1 (0x01) | Raw codec (0x55) | fr32-sha2-256-trunc254-padded-binary-tree multihash (0x1011) | multihash digest
        bytes memory cidData = new bytes(4 + multihashDigest.length);
        cidData[0] = 0x01; // CIDv1
        cidData[1] = 0x55; // Raw codec
        cidData[2] = 0x10; // fr32-sha2-256-trunc254-padded-binary-tree multihash (high byte)
        cidData[3] = 0x11; // fr32-sha2-256-trunc254-padded-binary-tree multihash (low byte)
        
        for (uint256 i = 0; i < multihashDigest.length; i++) {
            cidData[4 + i] = multihashDigest[i];
        }
        
        return Cids.Cid(cidData);
    }

    // Helper function to write a uvarint to a bytes array
    function _writeUvarint(bytes memory data, uint256 offset, uint256 value) internal pure returns (uint256) {
        while (value >= 0x80) {
            data[offset++] = bytes1(uint8(value | 0x80));
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
}
