// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.20;

import {IServiceProviderWorkerRegistry} from "../src/interfaces/IServiceProviderWorkerRegistry.sol";

/// @notice Test registry that approves only the snapshotted registration address.
contract UnknownWorkerRegistry is IServiceProviderWorkerRegistry {
    function isAuthorizedWorker(address registrationAddress, address attemptedAddress) external pure returns (bool) {
        return attemptedAddress == registrationAddress;
    }
}
