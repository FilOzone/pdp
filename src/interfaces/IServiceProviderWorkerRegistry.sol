// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.20;

/// @title IServiceProviderWorkerRegistry
/// @notice Minimal registry surface for resolving the current worker of a PDP provider.
interface IServiceProviderWorkerRegistry {
    /// @notice Resolve the live worker for an address that is or was a worker
    /// @param workerOrFormerWorker Current or previous worker address
    /// @return The current serviceProvider for that provider, or address(0) if unknown
    function currentWorker(address workerOrFormerWorker) external view returns (address);
}
