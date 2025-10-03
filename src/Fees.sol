// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.20;

/// @title PDPFees
/// @notice A library for calculating fees for the PDP.
library PDPFees {
    uint256 constant ATTO_FIL = 1;
    uint256 constant FIL_TO_ATTO_FIL = 1e18 * ATTO_FIL;

    // 0.1 FIL
    uint256 constant SYBIL_FEE = FIL_TO_ATTO_FIL / 10;

    // Fixed PDP proof fee per TiB (0.00023 FIL = 0.00023 * 1e18 AttoFIL = 230000000000000000 AttoFIL)
    // Based on fixed conversion rate: 1 FIL = 2.88 USD, with fee = 0.00067 USD / 2.88 USD = 0.00023 FIL per TiB
    uint256 public constant FEE_PER_TIB = 230000000000000000;

    // 1 TiB in bytes (2^40)
    uint256 constant TIB_IN_BYTES = 2 ** 40;

    // 2 USD/Tib/month is the current reward earned by Storage Providers
    uint256 constant ESTIMATED_MONTHLY_TIB_STORAGE_REWARD_USD = 2;
    // 1% of reward per period
    uint256 constant PROOF_FEE_PERCENTAGE = 1;
    // 4% of reward per period for gas limit left bound
    uint256 constant GAS_LIMIT_LEFT_PERCENTAGE = 4;
    // 5% of reward per period for gas limit right bound
    uint256 constant GAS_LIMIT_RIGHT_PERCENTAGE = 5;
    uint256 constant USD_DECIMALS = 1e18;
    // Number of epochs per month (30 days * 2880 epochs per day)
    uint256 constant EPOCHS_PER_MONTH = 86400;

    /// @notice Calculates the proof fee based on the gas fee and the raw size of the proof.
    /// @param estimatedGasFee The estimated gas fee in AttoFIL.
    /// @param filUsdPrice The price of FIL in USD.
    /// @param filUsdPriceExpo The exponent of the price of FIL in USD.
    /// @param rawSize The raw size of the proof in bytes.
    /// @param nProofEpochs The number of proof epochs.
    /// @return proof fee in AttoFIL
    /// @dev The proof fee is calculated based on the gas fee and the raw size of the proof
    /// The fee is 1% of the projected reward and is reduced in the case gas cost of proving is too high.
    function proofFeeWithGasFeeBound(
        uint256 estimatedGasFee, // in AttoFIL
        uint64 filUsdPrice,
        int32 filUsdPriceExpo,
        uint256 rawSize,
        uint256 nProofEpochs
    ) internal view returns (uint256) {
        require(
            estimatedGasFee > 0 || block.basefee == 0, "failed to validate: estimated gas fee must be greater than 0"
        );
        require(filUsdPrice > 0, "failed to validate: AttoFIL price must be greater than 0");
        require(rawSize > 0, "failed to validate: raw size must be greater than 0");

        // Calculate reward per epoch per byte (in AttoFIL)
        uint256 rewardPerEpochPerByte;
        if (filUsdPriceExpo >= 0) {
            rewardPerEpochPerByte = (ESTIMATED_MONTHLY_TIB_STORAGE_REWARD_USD * FIL_TO_ATTO_FIL)
                / (TIB_IN_BYTES * EPOCHS_PER_MONTH * filUsdPrice * (10 ** uint32(filUsdPriceExpo)));
        } else {
            rewardPerEpochPerByte = (
                ESTIMATED_MONTHLY_TIB_STORAGE_REWARD_USD * FIL_TO_ATTO_FIL * (10 ** uint32(-filUsdPriceExpo))
            ) / (TIB_IN_BYTES * EPOCHS_PER_MONTH * filUsdPrice);
        }

        // Calculate total reward for the proving period
        uint256 estimatedCurrentReward = rewardPerEpochPerByte * nProofEpochs * rawSize;

        // Calculate gas limits
        uint256 gasLimitRight = (estimatedCurrentReward * GAS_LIMIT_RIGHT_PERCENTAGE) / 100;
        uint256 gasLimitLeft = (estimatedCurrentReward * GAS_LIMIT_LEFT_PERCENTAGE) / 100;

        if (estimatedGasFee >= gasLimitRight) {
            return 0; // No proof fee if gas fee is above right limit
        } else if (estimatedGasFee >= gasLimitLeft) {
            return gasLimitRight - estimatedGasFee; // Partial discount on proof fee
        } else {
            return (estimatedCurrentReward * PROOF_FEE_PERCENTAGE) / 100;
        }
    }

    /// @notice Calculates the proof fee based on a fixed fee per TiB.
    /// @param rawSize The raw size of the proof in bytes.
    /// @param feePerTiB The fee per TiB in AttoFIL (can be overridden or use default).
    /// @return proof fee in AttoFIL
    /// @dev The proof fee is calculated as: (rawSize / TIB_IN_BYTES) * feePerTiB
    function flatProofFee(uint256 rawSize, uint256 feePerTiB) internal pure returns (uint256) {
        require(rawSize > 0, "failed to validate: raw size must be greater than 0");
        require(feePerTiB > 0, "failed to validate: fee per TiB must be greater than 0");
        
        // Calculate fee based on dataset size in TiB
        // fee = (rawSize / TIB_IN_BYTES) * feePerTiB
        // To avoid precision loss, we compute: (rawSize * feePerTiB) / TIB_IN_BYTES
        return (rawSize * feePerTiB) / TIB_IN_BYTES;
    }

    // sybil fee adds cost to adding state to the pdp verifier contract to prevent
    // wasteful state growth. 0.1 FIL
    function sybilFee() internal pure returns (uint256) {
        return SYBIL_FEE;
    }
}
