// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {PDPFees} from "../src/Fees.sol";

contract PDPFeesTest is Test {
    function testCalculateProofFee() public pure {
        uint256 rawSize = PDPFees.TIB_IN_BYTES; // 1 TiB
        uint256 expectedFee = PDPFees.FEE_PER_TIB;
        uint256 actualFee = PDPFees.calculateProofFee(rawSize);

        assertEq(actualFee, expectedFee, "Fee for 1 TiB should equal FEE_PER_TIB");
    }

    function testCalculateProofFeeHalfTiB() public pure {
        uint256 rawSize = PDPFees.TIB_IN_BYTES / 2; // 0.5 TiB
        uint256 expectedFee = PDPFees.FEE_PER_TIB / 2;
        uint256 actualFee = PDPFees.calculateProofFee(rawSize);

        assertEq(actualFee, expectedFee, "Fee for 0.5 TiB should be half of FEE_PER_TIB");
    }

    function testCalculateProofFeeMultipleTiB() public pure {
        uint256 rawSize = PDPFees.TIB_IN_BYTES * 10; // 10 TiB
        uint256 expectedFee = PDPFees.FEE_PER_TIB * 10;
        uint256 actualFee = PDPFees.calculateProofFee(rawSize);

        assertEq(actualFee, expectedFee, "Fee for 10 TiB should be 10x FEE_PER_TIB");
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testCalculateProofFeeZeroRawSize() public {
        vm.expectRevert("failed to validate: raw size must be greater than 0");
        PDPFees.calculateProofFee(0);
    }

    function testFeePerTiBConstant() public pure {
        // Verify the fee constant is set to 0.00023 FIL
        uint256 expectedFee = (23 * PDPFees.FIL_TO_ATTO_FIL) / 100000; // 0.00023 FIL
        assertEq(PDPFees.FEE_PER_TIB, expectedFee, "FEE_PER_TIB should be 0.00023 FIL");
    }

    function testSybilFee() public pure {
        uint256 fee = PDPFees.sybilFee();
        assertEq(fee, PDPFees.SYBIL_FEE, "Sybil fee should match the constant");
    }
}
