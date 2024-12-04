// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/// @notice Gas-efficient library for log2 calculations
library Log2 {
    /// @notice Calculates the binary logarithm (log base 2) of a number
    /// @dev Uses binary search approach for gas efficiency
    /// @param value The input value (must be greater than 0)
    /// @return result The floor of log base 2 of the input
    function log2(uint256 value) internal pure returns (uint256 result) {
        // Handle input validation
        require(value > 0, "Log2: value must be greater than 0");

        // Assembly implementation for maximum gas efficiency
        assembly {
            // For small numbers we can return early
            if lt(value, 2) {
                result := 0
            }
            if and(lt(value, 4), gt(value, 1)) {
                result := 1
            }
            if and(lt(value, 8), gt(value, 3)) {
                result := 2
            }
            if and(lt(value, 16), gt(value, 7)) {
                result := 3
            }

            // For larger numbers, use binary search
            if gt(value, 15) {
                value := shr(4, value) // divide by 16
                result := 4 // add 4 to result

                // Binary search through remaining bits
                if gt(value, 0xffffffff) {
                    value := shr(32, value)
                    result := add(result, 32)
                }
                if gt(value, 0xffff) {
                    value := shr(16, value)
                    result := add(result, 16)
                }
                if gt(value, 0xff) {
                    value := shr(8, value)
                    result := add(result, 8)
                }
                if gt(value, 0xf) {
                    value := shr(4, value)
                    result := add(result, 4)
                }
                if gt(value, 0x3) {
                    value := shr(2, value)
                    result := add(result, 2)
                }
                if gt(value, 0x1) {
                    result := add(result, 1)
                }
            }
        }
    }
}
