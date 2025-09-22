// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Cids} from "../Cids.sol";
import {IPDPTypes} from "./IPDPTypes.sol";

/// @title IPDPEvents
/// @notice Shared events for PDP contracts and consumers
interface IPDPEvents {
    event DataSetCreated(uint256 indexed setId, address indexed storageProvider);
    event StorageProviderChanged(
        uint256 indexed setId, address indexed oldStorageProvider, address indexed newStorageProvider
    );
    event DataSetDeleted(uint256 indexed setId, uint256 deletedLeafCount);
    event DataSetEmpty(uint256 indexed setId);
    event PiecesAdded(uint256 indexed setId, uint256[] pieceIds, Cids.Cid[] pieceCids);
    event PiecesRemoved(uint256 indexed setId, uint256[] pieceIds);
    event ProofFeePaid(uint256 indexed setId, uint256 fee, uint64 price, int32 expo);
    event PossessionProven(uint256 indexed setId, IPDPTypes.PieceIdAndOffset[] challenges);
    event NextProvingPeriod(uint256 indexed setId, uint256 challengeEpoch, uint256 leafCount);
    event ContractUpgraded(string version, address newImplementation);
}
