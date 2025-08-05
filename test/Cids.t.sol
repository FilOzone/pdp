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
