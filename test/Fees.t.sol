// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {PDPFees} from "../src/Fees.sol";

contract PDPFeesTest is Test {
    function testProofFeeWithGasFeeBoundZeroGasFee() public {
        vm.expectRevert("Estimated gas fee must be greater than 0");
        PDPFees.proofFeeWithGasFeeBound(0, 1, 1);
    }

    function testProofFeeWithGasFeeBoundZeroChallengeCount() public {
        vm.expectRevert("Challenge count must be greater than 0");
        PDPFees.proofFeeWithGasFeeBound(1, 0, 1);
    }

    function testProofFeeWithGasFeeBoundZeroProofSetLeafCount() public {
        vm.expectRevert("Proof set leaf count must be greater than 0");
        PDPFees.proofFeeWithGasFeeBound(1, 1, 0);
    }

    function testProofFeeWithGasFeeBoundHighGasFee() public pure {
        uint256 highGasFee = PDPFees.FIVE_PERCENT_DAILY_REWARD_ATTO_FIL;
        uint256 fee = PDPFees.proofFeeWithGasFeeBound(highGasFee, 1, 1);
        assertEq(fee, 0, "Fee should be 0 when gas fee is high");
    }

    function testProofFeeWithGasFeeBoundMediumGasFee() public pure {
        uint256 mediumGasFee = PDPFees.FOUR_PERCENT_DAILY_REWARD_ATTO_FIL + 1;
        uint256 fee = PDPFees.proofFeeWithGasFeeBound(mediumGasFee, 1, 1);
        assertEq(
            fee,
            PDPFees.FIVE_PERCENT_DAILY_REWARD_ATTO_FIL - mediumGasFee,
            "Fee should be partially discounted"
        );
    }

    function testProofFeeWithGasFeeBoundLowGasFee() public pure {
        uint256 lowGasFee = PDPFees.FOUR_PERCENT_DAILY_REWARD_ATTO_FIL - 1;
        uint256 challengeCount = 2;
        uint256 proofSetLeafCount = 4;
        uint256 fee = PDPFees.proofFeeWithGasFeeBound(
            lowGasFee,
            challengeCount,
            proofSetLeafCount
        );
        uint256 expectedFee = PDPFees.PROOF_PRICE_ATTO_FIL * challengeCount * 2; // log2(4) = 2
        assertEq(
            fee,
            expectedFee,
            "Fee should be calculated based on challenge count and proof set leaf count"
        );
    }

    function testProofFeeWithGasFeeBoundVaryingInputs() public pure {
        uint256[] memory gasFees = new uint256[](3);
        gasFees[0] = PDPFees.FOUR_PERCENT_DAILY_REWARD_ATTO_FIL / 2;
        gasFees[1] = PDPFees.FOUR_PERCENT_DAILY_REWARD_ATTO_FIL;
        gasFees[2] = PDPFees.FIVE_PERCENT_DAILY_REWARD_ATTO_FIL;

        uint256[] memory challengeCounts = new uint256[](3);
        challengeCounts[0] = 1;
        challengeCounts[1] = 5;
        challengeCounts[2] = 10;

        uint256[] memory proofSetLeafCounts = new uint256[](3);
        proofSetLeafCounts[0] = 2;
        proofSetLeafCounts[1] = 8;
        proofSetLeafCounts[2] = 16;

        for (uint256 i = 0; i < 3; i++) {
            for (uint256 j = 0; j < 3; j++) {
                for (uint256 k = 0; k < 3; k++) {
                    uint256 fee = PDPFees.proofFeeWithGasFeeBound(
                        gasFees[i],
                        challengeCounts[j],
                        proofSetLeafCounts[k]
                    );
                    assertTrue(fee >= 0, "Fee should always be non-negative");
                    if (
                        gasFees[i] >= PDPFees.FIVE_PERCENT_DAILY_REWARD_ATTO_FIL
                    ) {
                        assertEq(
                            fee,
                            0,
                            "Fee should be 0 when gas fee is high"
                        );
                    }
                }
            }
        }
    }

    function testSybilFee() public pure {
        uint256 fee = PDPFees.sybilFee();
        assertEq(fee, PDPFees.SYBIL_FEE, "Sybil fee should match the constant");
    }
}
