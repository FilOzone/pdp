// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Log2} from "../src/Log2.sol";

contract Log2Test is Test {
    function testLog2() public {
        // Test basic cases
        // Test basic cases
        vm.expectRevert("Log2: value must be greater than 0");
        Log2.log2(0);
        assertEq(Log2.log2(1), 0);

        assertEq(Log2.log2(2), 1);
        assertEq(Log2.log2(4), 2);
        assertEq(Log2.log2(8), 3);
        assertEq(Log2.log2(16), 4);
        assertEq(Log2.log2(32), 5);
        assertEq(Log2.log2(256), 8);

        // Test large numbers
        assertEq(Log2.log2(2 ** 100), 100);

        // Test non-power-of-two numbers
        assertEq(Log2.log2(3), 1);
        assertEq(Log2.log2(7), 2);
        assertEq(Log2.log2(10), 3);
        assertEq(Log2.log2(1000), 9);

        // Test max uint256
        assertEq(Log2.log2(type(uint256).max), 255);
    }
}
