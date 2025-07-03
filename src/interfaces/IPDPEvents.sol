// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IPDPTypes.sol";

/// @title IPDPEvents
/// @notice Shared events for PDP contracts and consumers
interface IPDPEvents {
    event ProofSetCreated(uint256 indexed setId, address indexed owner);
    event ProofSetOwnerChanged(uint256 indexed setId, address indexed oldOwner, address indexed newOwner);
    event ProofSetDeleted(uint256 indexed setId, uint256 deletedLeafCount);
    event ProofSetEmpty(uint256 indexed setId);
    event RootsAdded(uint256 indexed setId, uint256[] rootIds);
    event RootsRemoved(uint256 indexed setId, uint256[] rootIds);
    event ProofFeePaid(uint256 indexed setId, uint256 fee, uint64 price, int32 expo);
    event PossessionProven(uint256 indexed setId, IPDPTypes.RootIdAndOffset[] challenges);
    event NextProvingPeriod(uint256 indexed setId, uint256 challengeEpoch, uint256 leafCount);
    event PriceOracleFailure(bytes errorData);
    event ContractUpgraded(string version, address newImplementation);
} 