// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Cids} from "../src/Cids.sol";

contract CidsTest is Test {
    function testDigestRoundTrip() pure public {
        bytes memory prefix = "prefix";
        bytes32 digest = 0xbeadcafefacedeedfeedbabedeadbeefbeadcafefacedeedfeedbabedeadbeef;
        Cids.Cid memory c = Cids.cidFromDigest(prefix, digest);
        assertEq(c.data.length, 6 + 32);
        bytes32 foundDigest = Cids.digestFromCid(c);
        assertEq(foundDigest, digest);
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
}

contract CidsUvarintTestHelper {
    using Cids for *;

    // Expose _uvarintLength as public
    function uvarintLength(uint256 value) public pure returns (uint256) {
        return Cids._uvarintLength(value);
    }

    // Expose _writeUvarint as public
    function writeUvarint(uint256 value) public pure returns (bytes memory) {
        uint256 len = Cids._uvarintLength(value);
        bytes memory data = new bytes(len);
        Cids._writeUvarint(data, 0, value);
        return data;
    }
}

contract CidsCommpV2UvarintTest is Test {
    CidsUvarintTestHelper helper;

    function setUp() public {
        helper = new CidsUvarintTestHelper();
    }

    function testUvarintLength() public view {
        assertEq(helper.uvarintLength(0), 1);
        assertEq(helper.uvarintLength(127), 1);
        assertEq(helper.uvarintLength(128), 2);
        assertEq(helper.uvarintLength(255), 2);
        assertEq(helper.uvarintLength(300), 2);
        assertEq(helper.uvarintLength(16383), 2);
        assertEq(helper.uvarintLength(16384), 3);
        assertEq(helper.uvarintLength(2097151), 3);
        assertEq(helper.uvarintLength(2097152), 4);
    }

    function testWriteUvarint() public view {
        assertUvarint(0, hex"00");
        assertUvarint(127, hex"7f");
        assertUvarint(128, hex"8001");
        assertUvarint(255, hex"ff01");
        assertUvarint(300, hex"ac02");
        assertUvarint(16384, hex"808001");
    }

    function assertUvarint(uint256 value, bytes memory expected) public view {
        bytes memory actual = helper.writeUvarint(value);
        assertEq(actual, expected);
    }



}
