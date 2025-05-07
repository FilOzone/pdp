// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BitOps} from "./BitOps.sol";

library Cids {
    uint256 public constant COMMP_LEAF_SIZE = 32;
    //  0x01    0x55                0x9120
    // (cidv1)  (raw)  (fr32-sha2-256-trunc254-padded-binary-tree)
    bytes4 public constant COMMP_V2_PREFIX = hex"01559120";
    //  0x01    0x81e203                       0x9220                 0x20
    // (cidv1) (fil-commitment-unsealed) (sha2-256-trunc254-padded)  (uvarint(32))
    bytes7 public constant COMMP_V1_PREFIX = hex"0181e203922020";

    // A helper struct for events + getter functions to display digests as CommpV2 CIDs
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

    // Checks that cid matches commpv1 or commpv2.
    // If cid matches commpv2 then we validate that the on chain size matches commpv2 digest
    function validateCommP(Cid memory cid, uint256 leafCount) internal pure {
        if (hasPrefix7(cid, COMMP_V1_PREFIX)) {
            return;
        }
        if (!hasPrefix4(cid, COMMP_V2_PREFIX)) {
            revert "Cid must be commp"
        }
        // Validate commpv2
    }

    function hasPrefix4(bytes memory data, bytes4 prefix) internal pure returns (bool) {
        if (data.length < 4) return false;
        return bytes(data[:4]) == prefix;
    }

    function hasPrefix7(bytes memory data, bytes7 prefix) internal pure returns (bool) {
        if (data.length < 7) return false;
        return bytes(data[:7]) == prefix;
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
    // // The CID uses the Raw codec (0x55) and fr32-sha2-256-trunc254-padded-binary-tree multihash (0x1011).
    // // The digest format is: uvarint padding | uint8 height | 32 byte root data
    // function commpV2FromDigest(uint256 leafCount, bytes32 digest) internal pure returns (Cids.Cid memory) {
    //     // Calculate padding and height
 
    //     // Height is limited to 50 for PDP so packing into uint8 is safe for our use case
    //     uint8 height = uint8(256 - BitOps.clz(leafCount - 1) + 1);

    //     // padding = (next power of 2 - leafCount) * 127 / 128
    //     // padding is the pre-fr32 padded number of 0 bytes appended to data to hit a power of 2
    //     // after we do fr32 padding. 
    //     // since pdp assumes raw size includes fr32 padding this means we multiple by 127 / 128
    //     uint256 padding;
    //     // All CommPs need to be padded to at least 127 bytes pre fr32 
    //     // Since we take fr32 padded leaves this means 
    //     if (leafCount < 4) { 
    //     }
    //     } else {
    //         padding = ((1 << height) - leafCount) * 32 * 127 / 128;
    //     }

    //     // Create the multihash digest
    //     // Format: uvarint padding | uint8 height | 32 byte root data
    //     bytes memory multihashDigest = new bytes(33 + _uvarintLength(padding));
    //     uint256 offset = 0;
        
    //     // Write padding as uvarint
    //     offset = _writeUvarint(multihashDigest, offset, padding);
        
    //     // Write height
    //     multihashDigest[offset++] = bytes1(height);
        
    //     // Write root data
    //     for (uint256 i = 0; i < 32; i++) {
    //         multihashDigest[offset + i] = bytes1(digest << (i * 8));
    //     }
        
    //     // Create the CID
    //     // Format: CIDv1 (0x01) | Raw codec (0x55) | fr32-sha2-256-trunc254-padded-binary-tree multihash (0x1011) | multihash digest
    //     bytes memory cidData = new bytes(4 + multihashDigest.length);
    //     cidData[0] = 0x01; // CIDv1
    //     cidData[1] = 0x55; // Raw codec
    //     cidData[2] = 0x10; // fr32-sha2-256-trunc254-padded-binary-tree multihash (high byte)
    //     cidData[3] = 0x11; // fr32-sha2-256-trunc254-padded-binary-tree multihash (low byte)
    //     //  0x1011 
    //     //  0001 0000 0001 0001
    //     // 1001 0000 0001 0001 
    //     // 0x9011
        
    //     for (uint256 i = 0; i < multihashDigest.length; i++) {
    //         cidData[4 + i] = multihashDigest[i];
    //     }
        
    //     return Cids.Cid(cidData);
    // }

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

    // Helper function reading uvarints <= 256 bits 
    function _readUvarint(bytes memory data, unit256 offset) internal pure returns (uint256) {
        uint256 value = 0;
        while (data[offset] >= 0x80) {
            offset++;
            value = (value << 8) | uint256(data[offset]);
        }
        return value;
    }
}
