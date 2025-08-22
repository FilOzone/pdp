// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.20;

import {PDPListener} from "./PDPVerifier.sol";

/// @title IPDPProvingWindow
/// @notice Interface for PDP Service SLA specifications
interface IPDPProvingSchedule {
    /// @notice Returns the service associated with this proving schedule
    /// @return The PDP Service
    function service() external view returns (PDPListener);

    /// @notice Returns the number of epochs allowed before challenges must be resampled
    /// @return Maximum proving period in epochs
    function getMaxProvingPeriod() external view returns (uint64);

    /// @notice Returns the number of epochs at the end of a proving period during which proofs can be submitted
    /// @return Challenge window size in epochs
    function challengeWindow() external view returns (uint256);

    /// @notice Value for initializing the challenge window start for any data set assuming proving period starts now
    // @return Initial challenge window start in epochs
    function initChallengeWindowStart() external view returns (uint256);

    /// @notice Calculates the start of the next challenge window for a given data set
    /// @param setId The ID of the data set
    /// @return The block number when the next challenge window starts
    function nextChallengeWindowStart(uint256 setId) external view returns (uint256);

    /// @notice Returns the required number of challenges/merkle inclusion proofs per data set
    /// @return Number of challenges required per proof
    function getChallengesPerProof() external pure returns (uint64);
}
