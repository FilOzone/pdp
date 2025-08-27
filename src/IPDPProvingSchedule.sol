// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.20;

/// @title IPDPProvingSchedule
/// @notice Interface for PDP Service SLA specifications
interface IPDPProvingSchedule {
    /**
     * @notice Returns PDP configuration values
     * @return maxProvingPeriod Maximum number of epochs between proofs
     * @return challengeWindow Number of epochs for the challenge window
     * @return challengesPerProof Number of challenges required per proof
     * @return initChallengeWindowStart Initial challenge window start for new data sets assuming proving period starts now
     */
    function getPDPConfig()
        external
        view
        returns (
            uint64 maxProvingPeriod,
            uint256 challengeWindow,
            uint256 challengesPerProof,
            uint256 initChallengeWindowStart
        );

    /**
     * @notice Returns the start of the next challenge window for a data set
     * @param setId The ID of the data set
     * @return The block number when the next challenge window starts
     */
    function nextPDPChallengeWindowStart(uint256 setId) external view returns (uint256);
}
