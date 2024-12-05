// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;
import {BitOps} from "./BitOps.sol";

library PDPFees {
    uint256 constant ATTO_FIL = 1;
    uint256 constant ONE_FIL = 1e18 * ATTO_FIL;

    // 0.1 FIL
    uint256 constant SYBIL_FEE = ONE_FIL / 10;

    // assume 1FIL = $5 for now -> we can change this to use an oracle in PDP V1
    uint256 constant FIL_USD_PRICE = 5;

    // 2 USD/Tib/month is the current reward earned by Storage Providers
    uint256 constant MONTHLY_TIB_STORAGE_REWARD_USD = 2;

    uint256 constant DAILY_TIB_STORAGE_REWARD_ATTO_FIL =
        (MONTHLY_TIB_STORAGE_REWARD_USD * 1e18 * ATTO_FIL) /
            (30 * FIL_USD_PRICE);

    // PROOF_PRICE is currently set to 1% of the daily reward
    uint256 constant PROOF_PRICE_ATTO_FIL =
        (1 * DAILY_TIB_STORAGE_REWARD_ATTO_FIL) / 100;

    // 5% of daily reward
    uint256 constant FIVE_PERCENT_DAILY_REWARD_ATTO_FIL =
        (DAILY_TIB_STORAGE_REWARD_ATTO_FIL * 5) / 100;

    // 4% of daily reward
    uint256 constant FOUR_PERCENT_DAILY_REWARD_ATTO_FIL =
        (DAILY_TIB_STORAGE_REWARD_ATTO_FIL * 4) / 100;

    /// @return proof fee in AttoFIL
    function proofFeeWithGasFeeBound(
        uint256 estimatedGasFee,
        uint256 challengeCount,
        uint256 proofSetLeafCount
    ) internal pure returns (uint256) {
        require(
            estimatedGasFee > 0,
            "Estimated gas fee must be greater than 0"
        );
        require(challengeCount > 0, "Challenge count must be greater than 0");
        require(
            proofSetLeafCount > 0,
            "Proof set leaf count must be greater than 0"
        );

        if (estimatedGasFee >= FIVE_PERCENT_DAILY_REWARD_ATTO_FIL) {
            return 0; // No proof fee if gas fee is above 5% of the estimated reward
        } else if (estimatedGasFee >= FOUR_PERCENT_DAILY_REWARD_ATTO_FIL) {
            return FIVE_PERCENT_DAILY_REWARD_ATTO_FIL - estimatedGasFee; // Partial discount on proof fee
        } else {
            uint256 calculatedProofFee = (PROOF_PRICE_ATTO_FIL *
                challengeCount *
                BitOps.log2(proofSetLeafCount));
            return calculatedProofFee;
        }
    }

    // sybil fee adds cost to adding state to the pdp verifier contract to prevent
    // wasteful state growth. 0.1 FIL
    function sybilFee() internal pure returns (uint256) {
        return SYBIL_FEE;
    }
}
