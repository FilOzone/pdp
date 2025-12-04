// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.20;

/// @title PDPFees
/// @notice A library for calculating fees for the PDP.
library PDPFees {
    uint256 constant ATTO_FIL = 1;
    uint256 constant FIL_TO_ATTO_FIL = 1e18 * ATTO_FIL;

    // 0.1 FIL
    uint256 constant SYBIL_FEE = FIL_TO_ATTO_FIL / 10;

    // Default FIL-based proof fee: 0.00023 FIL per TiB (used for initialization)
    // Based on: 0.00067 USD per TiB / 2.88 USD per FIL = 0.00023 FIL per TiB
    uint96 constant DEFAULT_FEE_PER_TIB = 230000 gwei; // 0.00023 FIL in attoFIL

    // 1 TiB in bytes (2^40)
    uint256 constant TIB_IN_BYTES = 2 ** 40;

    /// @notice Calculates the proof fee based on the dataset size and a provided per-TiB fee.
    /// @param rawSize The raw size of the proof in bytes.
    /// @param feePerTiB The fee rate per TiB in AttoFIL (source of truth lives in PDPVerifier).
    /// @return proof fee in AttoFIL
    /// @dev The proof fee is calculated as: fee_perTiB * datasetSize_in_TiB
    function calculateProofFee(uint256 rawSize, uint96 feePerTiB) internal pure returns (uint256) {
        require(rawSize > 0, "failed to validate: raw size must be greater than 0");

        // Calculate fee as: (feePerTiB * rawSize) >> 40 (since TIB_IN_BYTES == 2**40)
        return (feePerTiB * rawSize) >> 40;
    }

    // sybil fee adds cost to adding state to the pdp verifier contract to prevent
    // wasteful state growth. 0.1 FIL
    function sybilFee() internal pure returns (uint256) {
        return SYBIL_FEE;
    }
}
