// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.20;

/// @title IServiceProviderWorkerRegistry
/// @notice Minimal registry surface for authorizing workers of a PDP provider.
interface IServiceProviderWorkerRegistry {
    /// @notice Whether `attemptedAddress` may act for the provider recorded as `registrationAddress`.
    /// @dev A registration may approve more than one worker. `registrationAddress` is the storage
    ///      provider snapshotted on the data set and may be a former worker. An unknown registration
    ///      is authorized only for `registrationAddress` itself, so pre-registry data sets stay operable.
    /// @param registrationAddress Provider address recorded on the data set.
    /// @param attemptedAddress Address attempting the storage-provider operation.
    /// @return True when `attemptedAddress` is an approved worker for that registration.
    function isAuthorizedWorker(address registrationAddress, address attemptedAddress) external view returns (bool);
}
