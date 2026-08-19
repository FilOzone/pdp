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
    /// @notice Deprecated. This event is no longer emitted; use {PiecesAddedV2} instead.
    /// @custom:deprecated Use {PiecesAddedV2} instead.
    event PiecesAdded(uint256 indexed setId, uint256[] pieceIds, Cids.Cid[] pieceCids);
    /// @notice Emitted for contiguous additions; piece ID at index `i` is `firstPieceId + i`.
    /// @dev Each packed CID header is right-aligned and zero-padded on the left. Reconstruct it by removing
    /// only the leading zero bytes from `header`, preserving any internal zeros, then appending `root`.
    event PiecesAddedV2(uint256 indexed setId, uint256 firstPieceId, Cids.PackedCid[] pieceCids);
    event PiecesScheduledForRemoval(uint256 indexed setId, uint256[] pieceIds);
    event PiecesRemoved(uint256 indexed setId, uint256[] pieceIds);
    event ProofFeePaid(uint256 indexed setId, uint256 fee);
    event FeeUpdateProposed(uint256 currentFee, uint256 newFee, uint256 effectiveTime);
    event PossessionProven(uint256 indexed setId, IPDPTypes.PieceIdAndOffset[] challenges);
    event NextProvingPeriod(uint256 indexed setId, uint256 challengeEpoch, uint256 leafCount);
    event ContractUpgraded(string version, address newImplementation);
}
